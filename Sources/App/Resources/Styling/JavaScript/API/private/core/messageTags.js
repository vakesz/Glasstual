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

/* Message tags: reactions (+draft/react) and replies (+draft/reply).

   Glasstual hands both to the view as one event. The line they refer
   to is updated in place here so that every style shows them the same
   way; a style only has to lay out the elements this file creates:

     .replyQuote      inserted at the start of a line's .innerMessage
                      when the line answers another one. Holds a
                      .replySender and a .replyExcerpt. Clicking it
                      scrolls to the referenced line.
     .reactions       appended after a line's .innerMessage. Holds one
                      .reaction per emoji with a .emoji and a .count.
                      data-mine="true" marks an emoji the local user
                      sent. The title lists who reacted.

   The style is told through Glasstual.tagMessageReceived() afterwards. */

var MessageTags = {};
var _MessageTags = {};

_MessageTags.lineWithMessageIdentifier = function(msgid) /* PRIVATE */
{
	if (!msgid) {
		return null;
	}

	var buffer = MessageBuffer.bufferElement();

	return buffer.querySelector('div.line[data-msgid="' + CSS.escape(msgid) + '"]');
};

/* The text of a line with the sender and any quote stripped: what a
   reply quote and a notification would show. */
MessageTags.excerptOfLine = function(line) /* PUBLIC */
{
	if (!line) {
		return "";
	}

	var message = line.querySelector(".innerMessage") || line.querySelector(".message");

	if (!message) {
		return "";
	}

	var clone = message.cloneNode(true);

	var strip = clone.querySelectorAll(".replyQuote, .reactions, .inlineMediaContainer, .deliveryFailure");

	for (var i = 0; i < strip.length; i++) {
		strip[i].remove();
	}

	var text = clone.textContent.replace(/\s+/g, " ").trim();

	if (text.length > 120) {
		text = text.substring(0, 119) + "…";
	}

	return text;
};

MessageTags.senderOfLine = function(line) /* PUBLIC */
{
	if (!line) {
		return "";
	}

	var sender = line.querySelector(".sender");

	if (sender && sender.dataset.nickname) {
		return sender.dataset.nickname;
	}

	return (sender ? sender.textContent.trim() : "");
};

/* Reply quotes */

_MessageTags.applyReplyToLine = function(line) /* PRIVATE */
{
	var msgid = line.dataset.replyTo;

	if (!msgid) {
		return;
	}

	var message = line.querySelector(".innerMessage");

	if (!message || message.querySelector(".replyQuote")) {
		return;
	}

	var referenced = _MessageTags.lineWithMessageIdentifier(msgid);

	var quote = document.createElement("span");

	quote.className = "replyQuote";
	quote.dataset.msgid = msgid;

	var sender = document.createElement("span");

	sender.className = "replySender";

	var excerpt = document.createElement("span");

	excerpt.className = "replyExcerpt";

	if (referenced) {
		sender.textContent = MessageTags.senderOfLine(referenced);
		excerpt.textContent = MessageTags.excerptOfLine(referenced);

		quote.title = excerpt.textContent;
	} else {
		quote.classList.add("unresolved");

		sender.textContent = "";
		excerpt.textContent = "Replying to an earlier message";
	}

	quote.appendChild(sender);
	quote.appendChild(excerpt);

	quote.addEventListener("click", _MessageTags.replyQuoteClicked, false);

	message.insertBefore(quote, message.firstChild);
};

_MessageTags.replyQuoteClicked = function(event) /* PRIVATE */
{
	event.preventDefault();
	event.stopPropagation();

	var msgid = event.currentTarget.dataset.msgid;

	var line = _MessageTags.lineWithMessageIdentifier(msgid);

	if (!line) {
		return;
	}

	Glasstual.scrollToElement(line.id);

	line.classList.remove("flash");

	/* Restart the animation when the same line is flashed twice. */
	void line.offsetWidth;

	line.classList.add("flash");
};

/* Reactions */

_MessageTags.reactionsOfLine = function(line) /* PRIVATE */
{
	var json = line.dataset.reactions;

	if (!json) {
		return {};
	}

	try {
		var parsed = JSON.parse(json);

		return ((parsed && typeof parsed === "object") ? parsed : {});
	} catch (error) {
		return {};
	}
};

_MessageTags.setReactionsOfLine = function(line, reactions) /* PRIVATE */
{
	var keys = Object.keys(reactions);

	if (keys.length === 0) {
		delete line.dataset.reactions;
	} else {
		line.dataset.reactions = JSON.stringify(reactions);
	}
};

_MessageTags.reactionsContainer = function(line, create) /* PRIVATE */
{
	var container = line.querySelector(".reactions");

	if (container || !create) {
		return container;
	}

	container = document.createElement("span");

	container.className = "reactions";

	var message = line.querySelector(".innerMessage") || line.querySelector(".message") || line;

	message.appendChild(container);

	return container;
};

_MessageTags.renderReactionsOfLine = function(line) /* PRIVATE */
{
	var reactions = _MessageTags.reactionsOfLine(line);

	var emojis = Object.keys(reactions);

	var container = _MessageTags.reactionsContainer(line, (emojis.length > 0));

	if (!container) {
		return;
	}

	while (container.firstChild) {
		container.removeChild(container.firstChild);
	}

	var localUser = _MessageTags.localUserNickname;

	for (var i = 0; i < emojis.length; i++) {
		var emoji = emojis[i];

		var nicknames = reactions[emoji];

		if (!Array.isArray(nicknames) || nicknames.length === 0) {
			continue;
		}

		var pill = document.createElement("span");

		pill.className = "reaction";
		pill.dataset.emoji = emoji;
		pill.title = nicknames.join(", ");

		if (localUser && nicknames.indexOf(localUser) !== -1) {
			pill.dataset.mine = "true";
		}

		var emojiElement = document.createElement("span");

		emojiElement.className = "emoji";
		emojiElement.textContent = emoji;

		var count = document.createElement("span");

		count.className = "count";
		count.textContent = String(nicknames.length);

		pill.appendChild(emojiElement);
		pill.appendChild(count);

		container.appendChild(pill);
	}

	if (container.childNodes.length === 0) {
		container.remove();
	}
};

_MessageTags.localUserNickname = null; /* PRIVATE */

/* Adds (or, for a repeat from the same nickname, leaves in place) one
   reaction. Returns the updated reactions of the line or null when no
   line carries the identifier. */
_MessageTags.addReaction = function(msgid, emoji, nickname) /* PRIVATE */
{
	var line = _MessageTags.lineWithMessageIdentifier(msgid);

	if (!line) {
		return null;
	}

	var reactions = _MessageTags.reactionsOfLine(line);

	var nicknames = reactions[emoji];

	if (!Array.isArray(nicknames)) {
		nicknames = [];
	}

	if (nicknames.indexOf(nickname) === -1) {
		nicknames.push(nickname);
	}

	reactions[emoji] = nicknames;

	_MessageTags.setReactionsOfLine(line, reactions);

	_MessageTags.renderReactionsOfLine(line);

	return reactions;
};

/* Entry points */

/* Called for every line added to the view, before the style hears of it. */
_MessageTags.lineAdded = function(lineNumber) /* PRIVATE */
{
	var line = document.getElementById("line-" + lineNumber);

	if (!line) {
		return;
	}

	_MessageTags.applyReplyToLine(line);

	if (line.dataset.reactions) {
		_MessageTags.renderReactionsOfLine(line);
	}
};

/* Called by Glasstual with the TAGMSG event. The event is extended with:

     fromLocalUser  - true when the local user sent the TAGMSG
     lineNumber     - the line a draft/react refers to, when in view
     reactions      - the updated reactions of that line */
_Glasstual.tagMessageReceived = function(event) /* PRIVATE */
{
	if (event.localUserNickname) {
		_MessageTags.localUserNickname = event.localUserNickname;
	}

	var tags = (event.tags || {});

	var emoji = tags["draft/react"];
	var msgid = tags["draft/reply"];

	if (emoji && msgid && event.sender) {
		var reactions = _MessageTags.addReaction(msgid, emoji, event.sender);

		if (reactions) {
			var line = _MessageTags.lineWithMessageIdentifier(msgid);

			event.lineNumber = line.id.lineNumberContents();
			event.reactions = reactions;
		}
	}

	Glasstual.tagMessageReceived(event);
};

/* Context menu

   The line under the pointer is reported ahead of the menu so that the
   app can offer Reply and React for it. */
_Glasstual._recordContextMenuLine = function(event) /* PRIVATE */
{
	var target = event.target;

	var line = ((target && target.lineContainer) ? target.lineContainer() : null);

	if (!line) {
		appPrivate.setLineContext(null);

		return;
	}

	appPrivate.setLineContext({
		"lineNumber" : line.id.lineNumberContents(),
		"msgid" : (line.dataset.msgid || ""),
		"lineType" : (line.dataset.lineType || ""),
		"nickname" : MessageTags.senderOfLine(line),
		"excerpt" : MessageTags.excerptOfLine(line)
	});
};

document.addEventListener("contextmenu", _Glasstual._recordContextMenuLine, true);
