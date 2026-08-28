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

/* Loading screen */
Glasstual.loadingScreenElement = function() /* PUBLIC */
{
	return document.getElementById("loadingScreen");
};

Glasstual.fadeOutLoadingScreen = function(bodyOp, topicOp) /* PUBLIC */
{
	var documentBody = Glasstual.documentBodyElement();

	var topicBar = Glasstual.topicBarElement();

	var loadingScreen = Glasstual.loadingScreenElement();

	/* Modify the opacity values of the various elements */
	loadingScreen.style.opacity = 0.00;

	documentBody.style.opacity = bodyOp;

	if (topicBar !== null) {
		topicBar.style.opacity = topicOp;
	}

	/* The fade time for the loading screen depends on the CSS of the actual
	style, but there is no reason it should take more than five (5) seconds.
	We will wait that amount of time before setting the overlay to hidden.
	Setting it to hidden makes it not copiable after it is not visible. */
	setTimeout(function() {
		var loadingScreen = Glasstual.loadingScreenElement();

		loadingScreen.style.display = "none";
	}, 5000);
};

/* Topic bar */
Glasstual._topicBarElementReference = null; /* PRIVATE */

Glasstual.topicBarElement = function() /* PUBLIC */
{
	if (Glasstual._topicBarElementReference === null) {
		Glasstual._topicBarElementReference = document.getElementById("topicBar");
	}

	return Glasstual._topicBarElementReference;
};

Glasstual.topicBarValue = function(asText) /* PUBLIC */
{
	var topicBar = Glasstual.topicBarElement();

	if (topicBar) {
		if (typeof asText === 'undefined' || asText === true) {
			return topicBar.textContent;
		} else {
			return topicBar.innerHTML;
		}
	}

	return null;
};

Glasstual.setTopicBarValue = function(topicValue, topicValueHTML) /* PUBLIC */
{
	var topicBar = Glasstual.topicBarElement();

	if (topicBar) {
		topicBar.innerHTML = topicValueHTML;

		Glasstual.topicBarValueChanged(topicValue);

		return true;
	}

	return false;
};

Glasstual.setTopicBarVisible = function(isVisible) /* PUBLIC */
{
	var topicBar = Glasstual.topicBarElement();

	if (topicBar) {
		if (isVisible) {
			topicBar.style.display = "";
		} else {
			topicBar.style.display = "none";
		}
	}
};

Glasstual.topicBarDoubleClicked = function() /* PUBLIC */
{
	appPrivate.topicBarDoubleClicked();
};

/* History indicator */
_Glasstual.historyIndicatorAdd = function(templateHTML) /* PRIVATE */
{
	_Glasstual.historyIndicatorRemove();

	MessageBuffer.bufferElementAppend(templateHTML);

	Glasstual.historyIndicatorAddedToView();
};

_Glasstual.historyIndicatorRemove = function() /* PRIVATE */
{
	var e = document.getElementById("mark");

	if (e) {
		e.remove();

		Glasstual.historyIndicatorRemovedFromView();
	}
};

/* Places the mark after the last line whose timestamp is at or before
the one given (a read marker another client set). Falls back to the
end of the buffer when every line is older. */
_Glasstual.historyIndicatorAddAfterTimestamp = function(templateHTML, timestamp) /* PRIVATE */
{
	_Glasstual.historyIndicatorRemove();

	var buffer = MessageBuffer.bufferElement();

	var lines = buffer.querySelectorAll("div.line");

	var insertBefore = null;

	for (var i = 0; i < lines.length; i++) {
		var line = lines[i];

		var lineTimestamp = parseFloat(line.dataset.timestamp);

		if (isNaN(lineTimestamp) === false && lineTimestamp > timestamp) {
			insertBefore = line;

			break;
		}
	}

	if (insertBefore === null) {
		MessageBuffer.bufferElementAppend(templateHTML);
	} else {
		insertBefore.insertAdjacentHTML('beforebegin', templateHTML);
	}

	Glasstual.historyIndicatorAddedToView();
};

/* Document body */
Glasstual._documentBodyElementReference = null; /* PRIVATE */

Glasstual.documentBodyElement = function() /* PUBLIC */
{
	if (Glasstual._documentBodyElementReference === null) {
		Glasstual._documentBodyElementReference = document.getElementById("body");
	}

	return Glasstual._documentBodyElementReference;
};

Glasstual.documentHTML = function() /* PUBLIC */
{
	return document.documentElement.innerHTML;
};

/* History */
_Glasstual.documentBodyAppendHistoric = function(templateHTML, lineNumbers, isReload) /* PRIVATE */
{
	var atBottom = GlasstualScroller.isScrolledToBottom();

	if (atBottom === false) {
		GlasstualScroller.saveRestorationFirstDataPoint();
	}

	MessageBuffer.bufferElementPrepend(templateHTML, lineNumbers);

	if (atBottom === false) {
		GlasstualScroller.saveRestorationSecondDataPoint();

		GlasstualScroller.restoreScrollPosition();
	}
};

/* History fetched from the server (chathistory BEFORE). The lines go
above everything in the buffer and the top is marked incomplete again
so that scrolling up asks for more. */
_Glasstual.documentBodyPrependRemoteHistory = function(templateHTML, lineNumbers) /* PRIVATE */
{
	var buffer = MessageBuffer.bufferElement();

	var firstLine = MessageBuffer.firstLineInBuffer(buffer);

	var atBottom = GlasstualScroller.isScrolledToBottom();

	if (atBottom === false) {
		GlasstualScroller.saveRestorationFirstDataPoint();
	}

	buffer.prepareForMutation();

	buffer.insertAdjacentHTML("afterbegin", templateHTML);

	MessageBuffer.noteRemoteHistoryPrepended(lineNumbers.length);

	try {
		_Glasstual.messageAddedToView(lineNumbers, true);
	} catch (error) {
		console.error(error);
	}

	if (atBottom === false) {
		GlasstualScroller.saveRestorationSecondDataPoint();

		GlasstualScroller.restoreScrollPosition();
	} else if (firstLine) {
		firstLine.scrollIntoViewAlignTop();
	}
};

/* Text */
Glasstual.changeTextSizeMultiplier = function(sizeMultiplier) /* PUBLIC */
{
	if (sizeMultiplier === 1.0) {
		document.body.style.fontSize = "";
	} else {
		document.body.style.fontSize = ((sizeMultiplier * 100.0) + "%");
	}
};

/* Line numbers */
HTMLDocument.prototype.getElementByLineNumber = function(lineNumber)
{
	lineNumber = lineNumber.standardizedLineNumber();

	return document.getElementById(lineNumber);
};

String.prototype.standardizedLineNumber = function() /* PUBLIC */
{
	if (this.indexOf("line-") !== 0) {
		return ("line-" + this);
	}

	return this;
};

String.prototype.lineNumberContents = function(lineNumber) /* PUBLIC */
{
	if (this.indexOf("line-") === 0) {
		return this.substr(5);
	}

	return this;
};

/* Given an element, find which .line element contains it. */
Element.prototype.lineContainer = function()
{
	var testElement = (function(element) {
		if (element.id && 
			element.id.indexOf("line-") === 0 &&
			element.classList &&
			element.classList.contains("line")) 
		{
			return element;
		}

		return null;
	});

	var line = null; /* default value */

	/* Test this element and all its parents */
	var currentElement = this;

	do {
		line = testElement(currentElement);

		if (line) {
			break;
		}
	} while (currentElement = currentElement.parentElement);

	/* Returns the line container or null */
	return line;
};

Element.prototype.lineNumberContents = function()
{
	var line = this.lineContainer();

	if (!line) {
		return null;
	}

	var lineNumber = line.id;

	return lineNumber.lineNumberContents();
};
