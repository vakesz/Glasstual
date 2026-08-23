/* Defined in: "Glasstual.app -> Contents -> Resources -> JavaScript -> API -> core.js" */

Glasstual.viewBodyDidLoad = function()
{
	Glasstual.fadeOutLoadingScreen(1.00, 0.95);
}

Glasstual.messageAddedToView = function(line, fromBuffer)
{
	var element = document.getElementById("line-" + line);

	ConversationTracking.updateNicknameWithNewMessage(element);
}

Glasstual.nicknameSingleClicked = function(e)
{
	ConversationTracking.nicknameSingleClickEventCallback(e);
}

/* The scrollback mark is a rule with a caption in the middle. The
   template carries the caption as data-caption; it is placed in a span
   so the rules on either side can stretch around it. */
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
