/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

#import "TDCFileTransferDialogSocketPrivate.h"

#import <Network/Network.h>

#include <arpa/inet.h>
#include <ifaddrs.h>
#include <net/if.h>

NS_ASSUME_NONNULL_BEGIN

NSErrorDomain const TDCFileTransferDialogSocketErrorDomain =
    @"TDCFileTransferDialogSocketErrorDomain";

#define _maximumReadLength (1024 * 64)

@interface TDCFileTransferDialogSocket ()
@property(nonatomic, weak, readwrite, nullable)
    id<TDCFileTransferDialogSocketDelegate>
        delegate;
@property(nonatomic, strong, readwrite) dispatch_queue_t delegateQueue;
@property(nonatomic, strong) dispatch_queue_t socketQueue;
@property(nonatomic, strong, nullable) nw_listener_t listener;
@property(nonatomic, strong, nullable) nw_connection_t connection;
@property(nonatomic, strong, nullable)
    TDCFileTransferDialogSocket *parentListener; // Accepted connections only
/* Accepted connections which have not become ready yet. Nothing else
 holds a strong reference to them (the nw_connection handlers capture
 weak self) so the listener keeps them alive until they are handed to
 the delegate or fail. Socket queue only. */
@property(nonatomic, strong)
    NSMutableSet<TDCFileTransferDialogSocket *> *pendingAcceptedConnections;
@property(nonatomic, assign, readwrite) BOOL isListener;
@property(nonatomic, assign) BOOL isOutboundConnection;
@property(nonatomic, assign) uint16_t nextListenPort;
@property(nonatomic, assign) uint16_t lastListenPort;
@property(nonatomic, assign)
    BOOL closed; // Set on the socket queue after an error or disconnect
@property(atomic, assign)
    BOOL invalidated; // Set by -disconnect; suppresses every delegate callback
@property(atomic, assign, readwrite) BOOL isConnected;
@property(nonatomic, copy, nullable) dispatch_block_t connectTimeoutBlock;
@end

@implementation TDCFileTransferDialogSocket

#pragma mark -
#pragma mark Initialization

- (instancetype)initWithDelegate:
                    (id<TDCFileTransferDialogSocketDelegate>)delegate
                   delegateQueue:(dispatch_queue_t)delegateQueue {
  NSParameterAssert(delegate != nil);
  NSParameterAssert(delegateQueue != nil);

  if ((self = [super init])) {
    self.delegate = delegate;
    self.delegateQueue = delegateQueue;

    dispatch_queue_attr_t attributes = dispatch_queue_attr_make_with_qos_class(
        DISPATCH_QUEUE_SERIAL, QOS_CLASS_DEFAULT, 0);

    NSString *queueName =
        [NSString stringWithFormat:@"Glasstual.TDCFileTransferDialogSocket-%@",
                                   [NSString stringWithUUID]];

    self.socketQueue = dispatch_queue_create(queueName.UTF8String, attributes);

    self.pendingAcceptedConnections = [NSMutableSet set];

    return self;
  }

  return nil;
}

- (void)dealloc {
  /* self cannot be captured here. Cancel whatever is still alive
   on the socket queue using local references only. */
  nw_listener_t listener = self->_listener;
  nw_connection_t connection = self->_connection;
  dispatch_block_t connectTimeoutBlock = self->_connectTimeoutBlock;

  if (listener == NULL && connection == NULL && connectTimeoutBlock == nil) {
    return;
  }

  dispatch_async(self->_socketQueue, ^{
    if (connectTimeoutBlock) {
      dispatch_block_cancel(connectTimeoutBlock);
    }

    if (listener) {
      nw_listener_cancel(listener);
    }

    if (connection) {
      nw_connection_cancel(connection);
    }
  });
}

#pragma mark -
#pragma mark Errors

+ (NSError *)errorWithCode:(TDCFileTransferDialogSocketError)code
               description:(NSString *)description {
  return [NSError errorWithDomain:TDCFileTransferDialogSocketErrorDomain
                             code:code
                         userInfo:@{NSLocalizedDescriptionKey : description}];
}

+ (NSError *)errorFromNetworkError:(nullable nw_error_t)networkError
                      fallbackCode:(TDCFileTransferDialogSocketError)code {
  if (networkError) {
    CFErrorRef cfError = nw_error_copy_cf_error(networkError);

    if (cfError) {
      return CFBridgingRelease(cfError);
    }
  }

  return [self errorWithCode:code description:@"Unknown socket error"];
}

#pragma mark -
#pragma mark Delegate Delivery

- (void)deliverToDelegate:
    (void (^)(id<TDCFileTransferDialogSocketDelegate> delegate))block {
  dispatch_async(self.delegateQueue, ^{
    if (self.invalidated) {
      return;
    }

    id<TDCFileTransferDialogSocketDelegate> delegate = self.delegate;

    if (delegate == nil) {
      return;
    }

    block(delegate);
  });
}

#pragma mark -
#pragma mark Teardown

/* Must be called on the socket queue */
- (void)tearDownNetworkObjects {
  if (self.connectTimeoutBlock) {
    dispatch_block_cancel(self.connectTimeoutBlock);

    self.connectTimeoutBlock = nil;
  }

  nw_listener_t listener = self.listener;

  if (listener) {
    self.listener = nil;

    nw_listener_cancel(listener);
  }

  nw_connection_t connection = self.connection;

  if (connection) {
    self.connection = nil;

    nw_connection_cancel(connection);
  }

  self.isConnected = NO;

  self.parentListener = nil;

  NSSet *pendingAcceptedConnections = [self.pendingAcceptedConnections copy];

  [self.pendingAcceptedConnections removeAllObjects];

  for (TDCFileTransferDialogSocket *connection in pendingAcceptedConnections) {
    [connection disconnect];
  }
}

/* Must be called on the socket queue */
- (void)failWithError:(NSError *)error {
  if (self.closed || self.invalidated) {
    return;
  }

  self.closed = YES;

  BOOL wasConnected = self.isConnected;

  BOOL isOutbound = self.isOutboundConnection;

  TDCFileTransferDialogSocket *parentListener = self.parentListener;

  [self tearDownNetworkObjects];

  /* An accepted connection which never became ready was never
   handed to the delegate so there is nobody to tell about it
   except the listener which is still holding on to it. */
  if (wasConnected == NO && isOutbound == NO) {
    [parentListener acceptedConnectionDidFail:self];

    return;
  }

  [self deliverToDelegate:^(id<TDCFileTransferDialogSocketDelegate> delegate) {
    if ([delegate respondsToSelector:@selector(socket:
                                         didDisconnectWithError:)]) {
      [delegate socket:self didDisconnectWithError:error];
    }
  }];
}

- (void)disconnect {
  self.invalidated = YES;

  dispatch_async(self.socketQueue, ^{
    self.closed = YES;

    [self tearDownNetworkObjects];
  });
}

#pragma mark -
#pragma mark Listening

- (void)listenOnPortRangeFrom:(uint16_t)startPort to:(uint16_t)endPort {
  dispatch_async(self.socketQueue, ^{
    if (self.closed || self.invalidated) {
      return;
    }

    self.isListener = YES;

    self.nextListenPort = startPort;
    self.lastListenPort = endPort;

    [self listenOnNextPort];
  });
}

/* Must be called on the socket queue */
- (void)listenOnNextPort {
  if (self.closed || self.invalidated) {
    return;
  }

  uint16_t port = self.nextListenPort;

  if (port == 0 || port > self.lastListenPort) {
    [self
        failToListenWithError:
            [self.class errorWithCode:TDCFileTransferDialogSocketErrorNoOpenPort
                          description:@"No port in the configured range could "
                                      @"be opened"]];

    return;
  }

  self.nextListenPort = (port + 1);

  nw_parameters_t parameters = nw_parameters_create_secure_tcp(
      NW_PARAMETERS_DISABLE_PROTOCOL, NW_PARAMETERS_DEFAULT_CONFIGURATION);

  char portString[8];

  snprintf(portString, sizeof(portString), "%hu", port);

  nw_listener_t listener = nw_listener_create_with_port(portString, parameters);

  if (listener == NULL) {
    [self listenOnNextPort];

    return;
  }

  self.listener = listener;

  __weak TDCFileTransferDialogSocket *weakSelf = self;

  nw_listener_set_queue(listener, self.socketQueue);

  nw_listener_set_state_changed_handler(
      listener, ^(nw_listener_state_t state, nw_error_t _Nullable error) {
        TDCFileTransferDialogSocket *strongSelf = weakSelf;

        if (strongSelf == nil || strongSelf.listener != listener) {
          return; // Stale listener
        }

        [strongSelf listener:listener changedState:state error:error];
      });

  nw_listener_set_new_connection_handler(
      listener, ^(nw_connection_t connection) {
        TDCFileTransferDialogSocket *strongSelf = weakSelf;

        if (strongSelf == nil || strongSelf.listener != listener) {
          nw_connection_cancel(connection);

          return;
        }

        [strongSelf acceptConnection:connection];
      });

  nw_listener_start(listener);
}

/* Must be called on the socket queue */
- (void)listener:(nw_listener_t)listener
    changedState:(nw_listener_state_t)state
           error:(nullable nw_error_t)error {
  switch (state) {
  case nw_listener_state_ready: {
    uint16_t port = nw_listener_get_port(listener);

    self.isConnected = YES;

    [self
        deliverToDelegate:^(id<TDCFileTransferDialogSocketDelegate> delegate) {
          if ([delegate respondsToSelector:@selector(socket:
                                               didStartListeningOnPort:)]) {
            [delegate socket:self didStartListeningOnPort:port];
          }
        }];

    break;
  }
  case nw_listener_state_failed: {
    NSError *listenError =
        [self.class errorFromNetworkError:error
                             fallbackCode:
                                 TDCFileTransferDialogSocketErrorNoOpenPort];

    if (self.isConnected) {
      /* The listener failed after it was ready. */
      [self failWithError:listenError];

      break;
    }

    LogToConsoleDebug("Failed to listen on port %{public}hu: %{public}@",
                      nw_listener_get_port(listener),
                      listenError.localizedDescription);

    /* The listener must be cancelled once it fails. */
    self.listener = nil;

    nw_listener_cancel(listener);

    [self listenOnNextPort];

    break;
  }
  case nw_listener_state_cancelled: {
    self.listener = nil;

    break;
  }
  default: {
    break;
  }
  }
}

/* Must be called on the socket queue */
- (void)failToListenWithError:(NSError *)error {
  if (self.closed || self.invalidated) {
    return;
  }

  self.closed = YES;

  [self tearDownNetworkObjects];

  [self deliverToDelegate:^(id<TDCFileTransferDialogSocketDelegate> delegate) {
    if ([delegate respondsToSelector:@selector(socket:
                                         didFailToListenWithError:)]) {
      [delegate socket:self didFailToListenWithError:error];
    }
  }];
}

/* Must be called on the socket queue */
- (void)acceptConnection:(nw_connection_t)connection {
  if (self.closed || self.invalidated) {
    nw_connection_cancel(connection);

    return;
  }

  id<TDCFileTransferDialogSocketDelegate> delegate = self.delegate;

  if (delegate == nil) {
    nw_connection_cancel(connection);

    return;
  }

  TDCFileTransferDialogSocket *accepted =
      [[TDCFileTransferDialogSocket alloc] initWithDelegate:delegate
                                              delegateQueue:self.delegateQueue];

  [self.pendingAcceptedConnections addObject:accepted];

  [accepted adoptConnection:connection acceptedByListener:self];
}

/* Called on the accepted connection's socket queue when that
 connection failed before it ever became ready. */
- (void)acceptedConnectionDidFail:(TDCFileTransferDialogSocket *)connection {
  dispatch_async(self.socketQueue, ^{
    [self.pendingAcceptedConnections removeObject:connection];
  });
}

/* Called on the listener's socket queue by an accepted connection once
 that connection is ready. */
- (void)acceptedConnectionIsReady:(TDCFileTransferDialogSocket *)connection {
  dispatch_async(self.socketQueue, ^{
    [self.pendingAcceptedConnections removeObject:connection];

    if (self.closed || self.invalidated) {
      [connection disconnect];

      return;
    }

    /* The delegate block retains the connection until delivery.
     From then on the delegate is responsible for keeping it. */
    [self
        deliverToDelegate:^(id<TDCFileTransferDialogSocketDelegate> delegate) {
          if ([delegate respondsToSelector:@selector(socket:
                                               didAcceptConnection:)]) {
            [delegate socket:self didAcceptConnection:connection];
          }
        }];
  });
}

#pragma mark -
#pragma mark Connecting

- (void)adoptConnection:(nw_connection_t)connection
     acceptedByListener:(TDCFileTransferDialogSocket *)listener {
  dispatch_async(self.socketQueue, ^{
    self.parentListener = listener;

    self.isOutboundConnection = NO;

    [self startConnection:connection];
  });
}

- (nullable NSString *)addressOfInterfaceNamed:(NSString *)interfaceName {
  struct ifaddrs *interfaces = NULL;

  if (getifaddrs(&interfaces) != 0) {
    return nil;
  }

  NSString *ipv4Address = nil;
  NSString *ipv6Address = nil;

  for (struct ifaddrs *interface = interfaces; interface != NULL;
       interface = interface->ifa_next) {
    if (interface->ifa_addr == NULL || (interface->ifa_flags & IFF_UP) == 0) {
      continue;
    }

    if (strcmp(interface->ifa_name, interfaceName.UTF8String) != 0) {
      continue;
    }

    char buffer[INET6_ADDRSTRLEN];

    sa_family_t family = interface->ifa_addr->sa_family;

    if (family == AF_INET && ipv4Address == nil) {
      struct sockaddr_in *address =
          (struct sockaddr_in *)(void *)interface->ifa_addr;

      if (inet_ntop(AF_INET, &address->sin_addr, buffer, sizeof(buffer))) {
        ipv4Address = @(buffer);
      }
    } else if (family == AF_INET6 && ipv6Address == nil) {
      struct sockaddr_in6 *address =
          (struct sockaddr_in6 *)(void *)interface->ifa_addr;

      if (IN6_IS_ADDR_LINKLOCAL(&address->sin6_addr)) {
        continue;
      }

      if (inet_ntop(AF_INET6, &address->sin6_addr, buffer, sizeof(buffer))) {
        ipv6Address = @(buffer);
      }
    }
  }

  freeifaddrs(interfaces);

  if (ipv4Address) {
    return ipv4Address;
  }

  return ipv6Address;
}

- (void)connectToHost:(NSString *)host
                 port:(uint16_t)port
         viaInterface:(nullable NSString *)interfaceName
              timeout:(NSTimeInterval)timeout {
  NSParameterAssert(host != nil);

  dispatch_async(self.socketQueue, ^{
    if (self.closed || self.invalidated) {
      return;
    }

    self.isOutboundConnection = YES;

    char portString[8];

    snprintf(portString, sizeof(portString), "%hu", port);

    nw_endpoint_t endpoint =
        nw_endpoint_create_host(host.UTF8String, portString);

    if (endpoint == NULL) {
      [self failWithError:
                [self.class errorWithCode:
                                TDCFileTransferDialogSocketErrorBadParameter
                              description:@"Invalid host address or port"]];

      return;
    }

    nw_parameters_t parameters = nw_parameters_create_secure_tcp(
        NW_PARAMETERS_DISABLE_PROTOCOL, NW_PARAMETERS_DEFAULT_CONFIGURATION);

    if (timeout > 0) {
      nw_protocol_stack_t protocolStack =
          nw_parameters_copy_default_protocol_stack(parameters);

      nw_protocol_options_t transportOptions =
          nw_protocol_stack_copy_transport_protocol(protocolStack);

      if (transportOptions) {
        nw_tcp_options_set_connection_timeout(transportOptions,
                                              (uint32_t)ceil(timeout));
      }
    }

    if (interfaceName.length > 0) {
      NSString *localAddress = [self addressOfInterfaceNamed:interfaceName];

      nw_endpoint_t localEndpoint = NULL;

      if (localAddress) {
        localEndpoint = nw_endpoint_create_host(localAddress.UTF8String, "0");
      }

      if (localEndpoint) {
        nw_parameters_set_local_endpoint(parameters, localEndpoint);
      } else {
        LogToConsoleError("Interface '%{public}@' has no usable address. Using "
                          "the default interface.",
                          interfaceName);
      }
    }

    nw_connection_t connection = nw_connection_create(endpoint, parameters);

    if (connection == NULL) {
      [self failWithError:
                [self.class errorWithCode:
                                TDCFileTransferDialogSocketErrorBadParameter
                              description:@"Could not create connection"]];

      return;
    }

    if (timeout > 0) {
      __weak TDCFileTransferDialogSocket *weakSelf = self;

      dispatch_block_t timeoutBlock = dispatch_block_create(0, ^{
        TDCFileTransferDialogSocket *strongSelf = weakSelf;

        if (strongSelf == nil || strongSelf.isConnected) {
          return;
        }

        [strongSelf
            failWithError:
                [strongSelf.class
                    errorWithCode:TDCFileTransferDialogSocketErrorConnectTimeout
                      description:@"Connection attempt timed out"]];
      });

      self.connectTimeoutBlock = timeoutBlock;

      dispatch_after(
          dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC)),
          self.socketQueue, timeoutBlock);
    }

    [self startConnection:connection];
  });
}

/* Must be called on the socket queue */
- (void)startConnection:(nw_connection_t)connection {
  if (self.closed || self.invalidated) {
    nw_connection_cancel(connection);

    return;
  }

  self.connection = connection;

  __weak TDCFileTransferDialogSocket *weakSelf = self;

  nw_connection_set_queue(connection, self.socketQueue);

  nw_connection_set_state_changed_handler(
      connection, ^(nw_connection_state_t state, nw_error_t _Nullable error) {
        TDCFileTransferDialogSocket *strongSelf = weakSelf;

        if (strongSelf == nil || strongSelf.connection != connection) {
          return; // Stale connection
        }

        [strongSelf connection:connection changedState:state error:error];
      });

  nw_connection_start(connection);
}

/* Must be called on the socket queue */
- (void)connection:(nw_connection_t)connection
      changedState:(nw_connection_state_t)state
             error:(nullable nw_error_t)error {
  switch (state) {
  case nw_connection_state_waiting: {
    NSError *waitError = [self.class
        errorFromNetworkError:error
                 fallbackCode:TDCFileTransferDialogSocketErrorConnectTimeout];

    LogToConsoleDebug("Connection is waiting: %{public}@",
                      waitError.localizedDescription);

    break;
  }
  case nw_connection_state_ready: {
    if (self.connectTimeoutBlock) {
      dispatch_block_cancel(self.connectTimeoutBlock);

      self.connectTimeoutBlock = nil;
    }

    self.isConnected = YES;

    TDCFileTransferDialogSocket *parentListener = self.parentListener;

    if (parentListener) {
      self.parentListener = nil;

      [parentListener acceptedConnectionIsReady:self];

      break;
    }

    [self
        deliverToDelegate:^(id<TDCFileTransferDialogSocketDelegate> delegate) {
          if ([delegate respondsToSelector:@selector(socketDidConnect:)]) {
            [delegate socketDidConnect:self];
          }
        }];

    break;
  }
  case nw_connection_state_failed: {
    [self failWithError:
              [self.class
                  errorFromNetworkError:error
                           fallbackCode:
                               TDCFileTransferDialogSocketErrorClosedByPeer]];

    break;
  }
  case nw_connection_state_cancelled: {
    self.connection = nil;

    break;
  }
  default: {
    break;
  }
  }
}

#pragma mark -
#pragma mark Reading

- (void)readData {
  dispatch_async(self.socketQueue, ^{
    if (self.closed || self.invalidated) {
      return;
    }

    nw_connection_t connection = self.connection;

    if (connection == NULL || self.isConnected == NO) {
      return;
    }

    __weak TDCFileTransferDialogSocket *weakSelf = self;

    nw_connection_receive(connection, 1, _maximumReadLength,
                          ^(dispatch_data_t _Nullable content,
                            nw_content_context_t _Nullable context,
                            bool isComplete, nw_error_t _Nullable error) {
                            TDCFileTransferDialogSocket *strongSelf = weakSelf;

                            if (strongSelf == nil ||
                                strongSelf.connection != connection) {
                              return;
                            }

                            [strongSelf didReceiveContent:content
                                               isComplete:isComplete
                                                    error:error];
                          });
  });
}

/* Must be called on the socket queue */
- (void)didReceiveContent:(nullable dispatch_data_t)content
               isComplete:(BOOL)isComplete
                    error:(nullable nw_error_t)error {
  if (self.closed || self.invalidated) {
    return;
  }

  if (content != NULL && dispatch_data_get_size(content) > 0) {
    NSMutableData *data =
        [NSMutableData dataWithCapacity:dispatch_data_get_size(content)];

    dispatch_data_apply(content, ^bool(dispatch_data_t region, size_t offset,
                                       const void *buffer, size_t size) {
      [data appendBytes:buffer length:size];

      return true;
    });

    [self
        deliverToDelegate:^(id<TDCFileTransferDialogSocketDelegate> delegate) {
          if ([delegate respondsToSelector:@selector(socket:didReadData:)]) {
            [delegate socket:self didReadData:data];
          }
        }];
  }

  if (error) {
    [self failWithError:
              [self.class
                  errorFromNetworkError:error
                           fallbackCode:
                               TDCFileTransferDialogSocketErrorClosedByPeer]];

    return;
  }

  if (isComplete) {
    [self failWithError:
              [self.class errorWithCode:
                              TDCFileTransferDialogSocketErrorClosedByPeer
                            description:@"Socket closed by remote peer"]];
  }
}

#pragma mark -
#pragma mark Writing

- (void)writeData:(NSData *)data timeout:(NSTimeInterval)timeout {
  NSParameterAssert(data != nil);

  dispatch_data_t content =
      dispatch_data_create(data.bytes, data.length, self.socketQueue,
                           DISPATCH_DATA_DESTRUCTOR_DEFAULT);

  dispatch_async(self.socketQueue, ^{
    if (self.closed || self.invalidated) {
      return;
    }

    nw_connection_t connection = self.connection;

    if (connection == NULL || self.isConnected == NO) {
      return;
    }

    __weak TDCFileTransferDialogSocket *weakSelf = self;

    dispatch_block_t timeoutBlock = nil;

    if (timeout > 0) {
      timeoutBlock = dispatch_block_create(0, ^{
        TDCFileTransferDialogSocket *strongSelf = weakSelf;

        if (strongSelf == nil || strongSelf.connection != connection) {
          return;
        }

        [strongSelf
            failWithError:
                [strongSelf
                        .class errorWithCode:
                                   TDCFileTransferDialogSocketErrorWriteTimeout
                                 description:@"Write operation timed out"]];
      });

      dispatch_after(
          dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC)),
          self.socketQueue, timeoutBlock);
    }

    nw_connection_send(
        connection, content, NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT, false,
        ^(nw_error_t _Nullable error) {
          if (timeoutBlock) {
            dispatch_block_cancel(timeoutBlock);
          }

          TDCFileTransferDialogSocket *strongSelf = weakSelf;

          if (strongSelf == nil || strongSelf.connection != connection) {
            return;
          }

          if (strongSelf.closed || strongSelf.invalidated) {
            return;
          }

          if (error) {
            [strongSelf
                failWithError:
                    [strongSelf.class
                        errorFromNetworkError:error
                                 fallbackCode:
                                     TDCFileTransferDialogSocketErrorClosedByPeer]];

            return;
          }

          [strongSelf deliverToDelegate:^(
                          id<TDCFileTransferDialogSocketDelegate> delegate) {
            if ([delegate respondsToSelector:@selector(socketDidWriteData:)]) {
              [delegate socketDidWriteData:strongSelf];
            }
          }];
        });
  });
}

@end

NS_ASSUME_NONNULL_END
