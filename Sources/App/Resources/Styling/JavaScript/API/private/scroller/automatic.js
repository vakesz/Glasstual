/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
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

"use strict";

/* ************************************************** */
/*                                                    */
/* DO NOT OVERRIDE ANYTHING BELOW THIS LINE           */
/*                                                    */
/* ************************************************** */

/* ************************************************** */
/*                     Visibility                     */
/* ************************************************** */

GlasstualScroller.documentIsVisible = undefined; /* PUBLIC */

_GlasstualScroller._documentVisibilityChangedCallback = function() /* PRIVATE */
{
	var documentHidden = document.hidden;

	if (documentHidden) {
		GlasstualScroller.documentIsVisible = false;
	} else {
		GlasstualScroller.documentIsVisible = true;

		GlasstualScroller.restoreScrolledToBottom();
	}
};

_GlasstualScroller._documentResizedCallback = function()
{
	GlasstualScroller.restoreScrolledToBottom();
};

/* ************************************************** */
/*                 Automatic Scroller                 */
/* ************************************************** */

_GlasstualScroller._performScrollTimeout = null; /* PRIVATE */
_GlasstualScroller._performScrollNextPass = undefined; /* PRIVATE */

_GlasstualScroller.performScrollPreflight = function() /* PRIVATE */
{
	/* Do nothing if we are already planning to scroll. */
	if (_GlasstualScroller._performScrollTimeout) {
		return;
	}

	if (_GlasstualScroller._performScrollNextPass) {
		return;
	}

	/* Are we at the bottom? */
	_GlasstualScroller._performScrollNextPass =
	GlasstualScroller.isScrolledToBottom();
};

_GlasstualScroller.performScrollCancel = function() /* PRIVATE */
{
	if (_GlasstualScroller._performScrollTimeout) {
		clearTimeout(_GlasstualScroller._performScrollTimeout);

		_GlasstualScroller._performScrollTimeout = null;
	}

	_GlasstualScroller._performScrollNextPass = undefined;
};

GlasstualScroller.performScroll = function() /* PUBLIC */
{
	/* Do nothing if we are already planning to scroll. */
	if (_GlasstualScroller._performScrollTimeout) {
		return;
	}

	/* Do not perform automatic scroll if we weren't at bottom. */
	if (!_GlasstualScroller._performScrollNextPass) {
		return;
	}

	var performAutomaticScroll = (function() {
		_GlasstualScroller._performScrollTimeout = null;
		_GlasstualScroller._performScrollNextPass = undefined;

		_GlasstualScroller.performScroll();
	});

	_GlasstualScroller._performScrollTimeout = 
	setTimeout(performAutomaticScroll, 0);
};

_GlasstualScroller.performScroll = function() /* PRIVATE */
{	
	/* Do not perform automatic scroll if is disabled. */
	if (!GlasstualScroller.automaticScrollingEnabled) {
		return;
	}

	/* Do not perform automatic scroll if the document is not visible. */
	if (!GlasstualScroller.documentIsVisible) {
		return;
	}

	/* Scroll to bottom */
	GlasstualScroller.scrollToBottom();
};

/* This function sets a flag that tells the scroller not to do anything,
regardless of whether it is visible or not. Visibility will control whether
the timer itself is activate, not this function. */
GlasstualScroller.automaticScrollingEnabled = true; /* PRIVATE */

GlasstualScroller.setAutomaticScrollingEnabled = function(enabled) /* PUBLIC */
{
	GlasstualScroller.automaticScrollingEnabled = enabled;
};

/* ************************************************** */
/*              Mutation Observer Helpers             */
/* ************************************************** */

HTMLDocument.prototype.prepareForMutation = function() /* PUBLIC */
{
	_GlasstualScroller.prepareForMutation();
};

HTMLDocument.prototype.cancelMutation = function() /* PUBLIC */
{
	_GlasstualScroller.cancelMutation();
};

Element.prototype.prepareForMutation = function() /* PUBLIC */
{
	document.prepareForMutation();
};

Element.prototype.cancelMutation = function() /* PUBLIC */
{
	document.cancelMutation();
};

_GlasstualScroller.prepareForMutation = function()
{
	_GlasstualScroller.performScrollPreflight();
};

_GlasstualScroller.cancelMutation = function()
{
	_GlasstualScroller.performScrollCancel();
};

/* ************************************************** */
/*                 Mutation Observer                  */
/* ************************************************** */

_GlasstualScroller._mutationObserver = null; /* PRIVATE */

_GlasstualScroller._mutationObserverCallback = function(mutations) /* PRIVATE */
{
	GlasstualScroller.performScroll();
};

_GlasstualScroller.createMutationObserver = function() /* PRIVATE */
{
	var buffer = MessageBuffer.bufferElement();

	var observer = new MutationObserver(_GlasstualScroller._mutationObserverCallback);

	observer.observe(
		buffer, 

		{
			childList: true,
			attributes: true,
			attributeFilter: ["wants-reveal", "style"], // for inline media
			subtree: true
		}
	);

	_GlasstualScroller._mutationObserver = observer;
};

/* ************************************************** */
/*                      Events                        */
/* ************************************************** */

window.addEventListener("resize", _GlasstualScroller._documentResizedCallback, false);

document.addEventListener("visibilitychange", _GlasstualScroller._documentVisibilityChangedCallback, false);

/* Populate initial visibility state and maybe create timer */
_GlasstualScroller._documentVisibilityChangedCallback();
