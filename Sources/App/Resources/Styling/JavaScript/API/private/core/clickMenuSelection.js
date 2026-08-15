/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2020 Codeux Software, LLC & respective contributors.
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

/* Selection */
Glasstual.currentSelection = function() /* PUBLIC */
{
	return window.getSelection().toString();
};

Glasstual.clearSelection = function() /* PUBLIC */
{
	window.getSelection().empty();
};

_Glasstual.clearSelectionAndPreventDefault = function() /* PRIVATE */
{
	Glasstual.clearSelection();

	event.preventDefault();
};

_Glasstual.recordSelection = function() /* PRIVATE */
{
	var selectedText = Glasstual.currentSelection();

	appPrivate.setSelection(selectedText);
};

_Glasstual._selectionChangedCallback = function() /* PRIVATE */
{
	_Glasstual.recordSelection();
};

_Glasstual.copySelectionOnMouseUpEvent = function() /* PRIVATE */
{
	if (window.event.metaKey || window.event.altKey) {
		return;
	}

	appPrivate.copySelectionWhenPermitted(
	   function(returnValue) {
			if (returnValue) {
				Glasstual.clearSelection();
			}
	   }
	);
};

_Glasstual._openGenericContextualMenu = function() /* PRIVATE */
{

};

Glasstual.openChannelNameContextualMenu = function() /* PUBLIC */
{
	_Glasstual.setPolicyChannelName();
};

Glasstual.openURLManagementContextualMenu = function() /* PUBLIC */
{
	_Glasstual.setPolicyURLAddress();
};

Glasstual.openStandardNicknameContextualMenu = function() /* PUBLIC */
{
	_Glasstual.setPolicyStandardNickname();
};

Glasstual.openInlineNicknameContextualMenu = function() /* PUBLIC */
{
	_Glasstual.setPolicyInlineNickname();
};

_Glasstual.setPolicyStandardNickname = function() /* PRIVATE */
{
	var userNickname = event.target.dataset.nickname;

	appPrivate.setNickname(userNickname);
};

_Glasstual.setPolicyInlineNickname = function() /* PRIVATE */
{
	var userNickname = event.target.textContent;

	var userMode = event.target.dataset.mode;

	if (userMode && userMode.length > 0 && userNickname.indexOf(userMode) === 0) {
		appPrivate.setNickname(userNickname.substring(1));
	} else {
		appPrivate.setNickname(userNickname);
	}
};

_Glasstual.setPolicyURLAddress = function() /* PRIVATE */
{
	appPrivate.setURLAddress(event.target.getAttribute("href"));
};

_Glasstual.setPolicyChannelName = function() /* PRIVATE */
{
	appPrivate.setChannelName(event.target.textContent);
};

/* Double click actions */
Glasstual._nicknameDoubleClickTimer = null;

Glasstual.nicknameMaybeWasDoubleClicked = function(e) /* PUBLIC */
{
	if (Glasstual._nicknameDoubleClickTimer) {
		clearTimeout(Glasstual._nicknameDoubleClickTimer);

		Glasstual._nicknameDoubleClickTimer = null;

		Glasstual.nicknameDoubleClicked(e);
	} else {
		Glasstual._nicknameDoubleClickTimer = setTimeout(function() {
			Glasstual._nicknameDoubleClickTimer = null;

			Glasstual.nicknameSingleClicked(e);
		}, 250);
	}
};

Glasstual.nicknameSingleClicked = function(e) /* PUBLIC */
{
	// API does not handle this action by default...
};

Glasstual.channelNameDoubleClicked = function() /* PUBLIC */
{
	_Glasstual.clearSelectionAndPreventDefault();

	_Glasstual.setPolicyChannelName();

	appPrivate.channelNameDoubleClicked();
};

Glasstual.nicknameDoubleClicked = function() /* PUBLIC */
{
	_Glasstual.clearSelectionAndPreventDefault();

	_Glasstual.setPolicyStandardNickname();

	appPrivate.nicknameDoubleClicked();
};

Glasstual.inlineNicknameDoubleClicked = function() /* PUBLIC */
{
	_Glasstual.clearSelectionAndPreventDefault();

	_Glasstual.setPolicyInlineNickname();

	appPrivate.nicknameDoubleClicked();
};

/* Bind to events */
document.addEventListener("contextmenu", _Glasstual._openGenericContextualMenu, false);

document.addEventListener("selectionchange", _Glasstual._selectionChangedCallback, false);
