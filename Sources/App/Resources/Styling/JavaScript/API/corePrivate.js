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

/* Private objects */
var _Glasstual = {};

/* Resource management */
Glasstual.initializeCore = function(resourcesPath)
{
	Glasstual.includeScriptResourceFile(resourcesPath + "/JavaScript/API/private/core/clickMenuSelection.js");
	Glasstual.includeScriptResourceFile(resourcesPath + "/JavaScript/API/private/core/documentBody.js");
	Glasstual.includeScriptResourceFile(resourcesPath + "/JavaScript/API/private/core/events.js");
	Glasstual.includeScriptResourceFile(resourcesPath + "/JavaScript/API/private/core/inlineMedia.js");
	Glasstual.includeScriptResourceFile(resourcesPath + "/JavaScript/API/private/core/messageBuffer.js");
	Glasstual.includeScriptResourceFile(resourcesPath + "/JavaScript/API/private/core/messageTags.js");
	Glasstual.includeScriptResourceFile(resourcesPath + "/JavaScript/API/private/core/scrollTo.js");
	Glasstual.includeScriptResourceFile(resourcesPath + "/JavaScript/API/private/scroller/state.js");
	Glasstual.includeScriptResourceFile(resourcesPath + "/JavaScript/API/private/scroller/automatic.js");

	Glasstual.includeScriptResourceFile(resourcesPath + "/JavaScript/API/private/conversationTracking.js");
	Glasstual.includeScriptResourceFile(resourcesPath + "/JavaScript/API/private/scriptSink.js");
};

/* Remote resources are refused unless they come over HTTPS from a host the
   app knows about. This page is a file:// document holding the native "app"
   bridge, so whoever serves a <script> here owns that bridge. Keep this list
   in step with InlineResourceHostPolicy.permittedHosts on the Swift side. */
Glasstual.permittedResourceHosts = ["platform.twitter.com"];

Glasstual.resourceFileIsPermitted = function(file)
{
	if (typeof file !== "string" || file.length === 0) {
		return false;
	}

	var scheme = /^([a-zA-Z][a-zA-Z0-9+.\-]*):/.exec(file);

	/* Resources copied into the theme's temporary directory by the app
	   arrive as plain filesystem paths, without a scheme. */
	if (scheme === null) {
		return true;
	}

	var schemeName = scheme[1].toLowerCase();

	if (schemeName === "file") {
		return true;
	}

	if (schemeName !== "https") {
		console.error("Refusing resource with scheme '" + schemeName + "'");

		return false;
	}

	var host = null;

	try {
		host = new URL(file).hostname.toLowerCase();
	} catch (error) {
		console.error("Refusing resource with an unparsable address");

		return false;
	}

	if (Glasstual.permittedResourceHosts.indexOf(host) < 0) {
		console.error("Refusing resource from host '" + host + "'");

		return false;
	}

	return true;
};

Glasstual.includeStyleResourceFile = function(file)
{
	if (Glasstual.resourceFileIsPermitted(file) === false) {
		return;
	}

	if (/loaded|complete/.test(document.readyState)) {
		var newFile = document.createElement("link");

		newFile.charset = "UTF-8";
		newFile.href = file;
		newFile.media = "screen";
		newFile.rel = "stylesheet";
		newFile.type = "text/css";

		document.getElementsByTagName("HEAD")[0].appendChild(newFile);
	} else {
		document.write('<link href="' + file + '" media="screen" rel="stylesheet" type="text/css" />');
	}
};

Glasstual.includeScriptResourceFile = function(file)
{
	if (Glasstual.resourceFileIsPermitted(file) === false) {
		return;
	}

	if (/loaded|complete/.test(document.readyState)) {
		var newFile = document.createElement("script");

		newFile.setAttribute("charset", "UTF-8");

		newFile.charset = "UTF-8";
		newFile.src = file;
		newFile.type = "text/javascript";

		document.getElementsByTagName("HEAD")[0].appendChild(newFile);
	} else {
		document.write('<script type="text/javascript" src="' + file + '"></scr' + 'ipt>');
	}
};
