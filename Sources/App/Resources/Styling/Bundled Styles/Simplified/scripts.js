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
