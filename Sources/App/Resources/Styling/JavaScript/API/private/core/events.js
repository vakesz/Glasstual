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

Glasstual.finishedLoadingView = false; /* PUBLIC */
Glasstual.finishedLoadingHistory = false; /* PUBLIC */

/* State management */
_Glasstual.notifyDidBecomeVisible = function() /* PRIVATE */
{
	Glasstual.clearSelection();

	document.body.dataset.visible = "true";
};

_Glasstual.notifyDidBecomeHidden = function() /* PRIVATE */
{
	Glasstual.clearSelection();

	document.body.dataset.visible = false;
};

_Glasstual.notifySelectionChanged = function(isSelected) /* PRIVATE */
{
	/* Changing this attribute may change the height of the body 
	because of the disappearance and reappearance of the topic.
	It is easiest for us to keep a record of where we were before
	changing this attribute, then scroll to that. */
	var scrolledToBottom = GlasstualScroller.isScrolledToBottom();

	if (isSelected) {
		document.body.dataset.selected = "true";
	} else {
		document.body.dataset.selected = "false";
	}

	if (scrolledToBottom) {
		GlasstualScroller.scrollToBottom();
	}
};

Glasstual.viewBodyDidLoadInt = function() /* PRIVATE */
{
	console.warn("Glasstual.viewBodyDidLoadInt() is deprecated. Use _Glasstual.viewBodyDidLoad() instead.");

	_Glasstual.viewBodyDidLoad();
};

_Glasstual._viewBodyDidLoadAnimationFrame = null; /* PRIVATE */

_Glasstual.viewBodyDidLoad = function() /* PRIVATE */
{
	/* Wait until element is available before binding to it. */
	_GlasstualScroller.bindToBestElement();

	/* On styles with a dark background, a white flash occurs because there is a very
	 small delay between the view being created and the background process laying out
	 its contents. To work around this, Glasstual presents an overlay view that matches
	 the background color of the style. We then request an animation frame that calls
	 app.finishedLayingOutView, instructing Glasstual that it can destroy the overlay view. */

	_Glasstual._viewBodyDidLoadAnimationFrame =
	window.requestAnimationFrame(function() {
		_Glasstual._viewBodyDidLoad();
	});
};

_Glasstual._viewBodyDidLoad = function() /* PRIVATE */
{
	_Glasstual._viewBodyDidLoadAnimationFrame = null;

	appPrivate.finishedLayingOutView();

	Glasstual.viewBodyDidLoad();
};

_Glasstual.viewFinishedLoading = function(configuration) /* PRIVATE */
{
	var isSelected = configuration.selected;
	var isVisible = configuration.visible;
	var isReloadingTheme = configuration.reloadingTheme;
	var textSizeMultiplier = configuration.textSizeMultiplier;
	var scrollbackSoftLimit = configuration.scrollbackSoftLimit;
	var scrollbackHardLimit = configuration.scrollbackHardLimit;

	_GlasstualScroller.createMutationObserver();

	if (isVisible) {
		_Glasstual.notifyDidBecomeVisible();

		_Glasstual.notifySelectionChanged(isSelected);
	} else {
		_Glasstual.notifyDidBecomeHidden();
	}

	if (isReloadingTheme) {
		Glasstual.viewFinishedReload();
	} else {
		Glasstual.viewFinishedLoading();
	}

	/* If this view is not visible to the user, then cancel the animation
	 frame set by Glasstual.viewBodyDidLoadInt() because there is no use for it. */
	if (isVisible === false && isSelected === false) {
		if (_Glasstual._viewBodyDidLoadAnimationFrame) {
			window.cancelAnimationFrame(_Glasstual._viewBodyDidLoadAnimationFrame);

			_Glasstual._viewBodyDidLoad();
		}
	}

	Glasstual.changeTextSizeMultiplier(textSizeMultiplier);

	_MessageBuffer.setBufferLimits(scrollbackSoftLimit, scrollbackHardLimit);
};

_Glasstual.viewFinishedLoadingHistory = function() /* PRIVATE */
{
	Glasstual.finishedLoadingHistory = true;

	Glasstual.viewFinishedLoadingHistory();
};

_Glasstual.messageAddedToView = function(lineNumber, fromBuffer) /* PRIVATE */
{
	/* Allow lineNumber to be an array of line numbers or a single line number. */
	if (Array.isArray(lineNumber)) {
		for (var i = 0; i < lineNumber.length; i++) {
			_MessageTags.lineAdded(lineNumber[i]);

			Glasstual.messageAddedToView(lineNumber[i], fromBuffer);
		}
	} else {
		_MessageTags.lineAdded(lineNumber);

		Glasstual.messageAddedToView(lineNumber, fromBuffer);
	}

	appPrivate.notifyLinesAddedToView(lineNumber);
};

/* Delivery state of a line the local user sent (labeled-response +
   echo-message). The line element is updated in place, then the style
   is told through Glasstual.lineDeliveryStateChanged(). */
_Glasstual.lineDeliveryStateChanged = function(lineNumber, state, msgid, reason) /* PRIVATE */
{
	var line = document.getElementById("line-" + lineNumber);

	if (line) {
		line.setAttribute("data-delivery-state", state);

		if (msgid) {
			line.setAttribute("data-msgid", msgid);
		}

		var failure = line.querySelector(".deliveryFailure");

		if (state === "failed") {
			if (failure === null) {
				failure = document.createElement("span");

				failure.className = "deliveryFailure";

				var message = line.querySelector(".innerMessage");

				if (message) {
					message.appendChild(failure);
				} else {
					line.appendChild(failure);
				}
			}

			failure.textContent = (reason || "");
		} else if (failure) {
			failure.parentNode.removeChild(failure);
		}
	}

	Glasstual.lineDeliveryStateChanged(lineNumber, state, msgid, reason);
};

_Glasstual.messageRemovedFromView = function(lineNumber) /* PRIVATE */
{
	/* Allow lineNumber to be an array of line numbers or a single line number. */
	if (Array.isArray(lineNumber)) {
		for (var i = 0; i < lineNumber.length; i++) {
			Glasstual.messageRemovedFromView(lineNumber[i]);
		}
	} else {
		Glasstual.messageRemovedFromView(lineNumber);
	}

	appPrivate.notifyLinesRemovedFromView(lineNumber);
};

/* Events */
_Glasstual._mouseUpEventCallback = function() /* PRIVATE */
{
	_Glasstual.copySelectionOnMouseUpEvent();
};

/* Bind to events */
document.addEventListener("mouseup", _Glasstual._mouseUpEventCallback, false);
