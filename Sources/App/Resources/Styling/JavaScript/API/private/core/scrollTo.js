/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
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

/* Scrolling */
Glasstual.scrollToBottomOfView = function(fireNotification) /* PUBLIC */
{
	GlasstualScroller.scrollToBottom();

	if (fireNotification) {
		Glasstual.viewPositionMovedToBottom();
	}
};

Glasstual.scrollToTopOfView = function(fireNotification) /* PUBLIC */
{
	GlasstualScroller.scrollToTop();

	if (fireNotification) {
		Glasstual.viewPositionMovedToTop();
	}
};

Glasstual.scrollToLine = function(lineNumber) /* PUBLIC */
{
	Glasstual.jumpToLine(lineNumber);
};

Glasstual.jumpToLine = function(lineNumber) /* PUBLIC */
{
	MessageBuffer.jumpToLine(
		lineNumber, 

		(function(success) {
			var scrolledToBottom = false;

			if (success) {
				scrolledToBottom = GlasstualScroller.isScrolledToBottom();

				Glasstual.viewPositionMovedToLine(lineNumber);
			}

			appPrivate.notifyJumpToLineCallback(lineNumber, success, scrolledToBottom);
		})
	);
};

Glasstual.scrollToElement = function(elementName) /* PUBLIC */
{
	var element = document.getElementById(elementName);

	if (element) {
		GlasstualScroller.scrollElementToCenter(element);

		return true;
	}

	return false;
};

Glasstual.scrollToHistoryIndicator = function() /* PUBLIC */
{
	if (Glasstual.scrollToElement("mark")) {
		Glasstual.viewPositionModToHistoryIndicator();
	}
};
