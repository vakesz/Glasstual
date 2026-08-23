/* Defined in: "Glasstual.app -> Contents -> Resources -> JavaScript -> API -> core.js" */

/* Messages from the same person within this many seconds are grouped:
   one sender name above, a tail on the last bubble only. */
var Bubbles = {
	groupInterval : 180,

	/* A caption with the time is placed between two messages further
	   apart than this. */
	separatorInterval : 900
};

Glasstual.viewBodyDidLoad = function()
{
	Glasstual.fadeOutLoadingScreen(1.00, 0.95);
}

Glasstual.messageAddedToView = function(line, fromBuffer)
{
	var element = document.getElementById("line-" + line);

	if (!element) {
		return;
	}

	Bubbles.decorateLine(element);

	ConversationTracking.updateNicknameWithNewMessage(element);
}

Glasstual.nicknameSingleClicked = function(e)
{
	ConversationTracking.nicknameSingleClickEventCallback(e);
}

Glasstual.historyIndicatorAddedToView = function()
{
	var mark = document.getElementById("mark");

	if (!mark || mark.querySelector(".markCaption")) {
		return;
	}

	var caption = document.createElement("span");

	caption.className = "markCaption";
	caption.textContent = (mark.dataset.caption || "");

	mark.appendChild(caption);
}

/* Lines are grouped and separated on the way in. A line inserted above
   older ones (history) is decorated against its neighbours as well. */

Bubbles.isChatLine = function(line)
{
	if (!line || !line.classList.contains("line")) {
		return false;
	}

	var type = line.dataset.lineType;

	return (type === "privmsg" || type === "action" || type === "notice");
};

Bubbles.senderOfLine = function(line)
{
	var sender = line.querySelector(".sender");

	if (sender && sender.dataset.nickname) {
		return sender.dataset.nickname;
	}

	return (sender ? sender.textContent.trim() : "");
};

Bubbles.isServiceNotice = function(line)
{
	if (line.dataset.lineType !== "notice") {
		return false;
	}

	var nickname = Bubbles.senderOfLine(line).toLowerCase();

	return (nickname.length === 0 || /serv$/.test(nickname) || nickname === "global");
};

Bubbles.previousLine = function(line)
{
	var previous = line.previousElementSibling;

	while (previous) {
		if (previous.classList.contains("line")) {
			return previous;
		}

		previous = previous.previousElementSibling;
	}

	return null;
};

Bubbles.nextLine = function(line)
{
	var next = line.nextElementSibling;

	while (next) {
		if (next.classList.contains("line")) {
			return next;
		}

		next = next.nextElementSibling;
	}

	return null;
};

Bubbles.sameGroup = function(a, b)
{
	if (!Bubbles.isChatLine(a) || !Bubbles.isChatLine(b)) {
		return false;
	}

	if (a.classList.contains("service") || b.classList.contains("service")) {
		return false;
	}

	if (a.dataset.lineType !== b.dataset.lineType && (a.dataset.lineType === "notice" || b.dataset.lineType === "notice")) {
		return false;
	}

	if (a.dataset.memberType !== b.dataset.memberType) {
		return false;
	}

	if (Bubbles.senderOfLine(a) !== Bubbles.senderOfLine(b)) {
		return false;
	}

	var ta = parseFloat(a.dataset.timestamp);
	var tb = parseFloat(b.dataset.timestamp);

	if (isNaN(ta) || isNaN(tb)) {
		return false;
	}

	/* Anything that sits between the two (a date caption, the mark)
	   breaks the group. */
	var between = a.nextElementSibling;

	while (between && between !== b) {
		if (!between.classList.contains("timeSeparator")) {
			return false;
		}

		between = between.nextElementSibling;
	}

	return (Math.abs(tb - ta) <= Bubbles.groupInterval);
};

Bubbles.setGroupPosition = function(line, joinsPrevious, joinsNext)
{
	line.classList.remove("groupStart", "groupMiddle", "groupEnd", "solo");

	if (joinsPrevious && joinsNext) {
		line.classList.add("groupMiddle");
	} else if (joinsPrevious) {
		line.classList.add("groupEnd");
	} else if (joinsNext) {
		line.classList.add("groupStart");
	} else {
		line.classList.add("solo");
	}
};

Bubbles.decorateLine = function(line)
{
	if (Bubbles.isServiceNotice(line)) {
		line.classList.add("service");
	}

	if (line.dataset.lineType === "action") {
		var message = line.querySelector(".innerMessage");

		if (message) {
			message.dataset.actionSender = Bubbles.senderOfLine(line);
		}
	}

	if (!Bubbles.isChatLine(line)) {
		return;
	}

	var previous = Bubbles.previousLine(line);
	var next = Bubbles.nextLine(line);

	Bubbles.insertTimeSeparatorIfNeeded(previous, line);

	var joinsPrevious = (previous !== null && Bubbles.sameGroup(previous, line));
	var joinsNext = (next !== null && Bubbles.sameGroup(line, next));

	Bubbles.setGroupPosition(line, joinsPrevious, joinsNext);

	if (joinsPrevious) {
		var previousJoinsBefore = (previous.classList.contains("groupMiddle") || previous.classList.contains("groupEnd"));

		Bubbles.setGroupPosition(previous, previousJoinsBefore, true);
	}

	if (joinsNext) {
		var nextJoinsAfter = (next.classList.contains("groupStart") || next.classList.contains("groupMiddle"));

		Bubbles.setGroupPosition(next, true, nextJoinsAfter);
	}
};

Bubbles.insertTimeSeparatorIfNeeded = function(previous, line)
{
	if (!previous) {
		return;
	}

	var sibling = line.previousElementSibling;

	if (sibling && (sibling.classList.contains("timeSeparator") ||
					sibling.classList.contains("date_indicator") ||
					sibling.classList.contains("session_indicator"))) {
		return;
	}

	var tp = parseFloat(previous.dataset.timestamp);
	var tl = parseFloat(line.dataset.timestamp);

	if (isNaN(tp) || isNaN(tl) || (tl - tp) < Bubbles.separatorInterval) {
		return;
	}

	var time = line.querySelector(".time");

	var caption = "";

	if (time) {
		caption = (time.getAttribute("title") || time.textContent).trim();
	}

	if (caption.length === 0) {
		return;
	}

	var separator = document.createElement("div");

	separator.className = "timeSeparator";

	var span = document.createElement("span");

	span.textContent = caption;

	separator.appendChild(span);

	line.parentNode.insertBefore(separator, line);
};
