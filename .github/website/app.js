const repository = "vakesz/Glasstual";
const releaseEndpoint = `https://api.github.com/repos/${repository}/releases/latest`;
const releaseFallback = `https://github.com/${repository}/releases/latest`;

const downloadButtons = [
  document.querySelector("#download-button"),
  document.querySelector("#download-button-bottom"),
];
const releaseNote = document.querySelector("#release-note");

async function loadLatestRelease() {
  try {
    const response = await fetch(releaseEndpoint, {
      headers: { Accept: "application/vnd.github+json" },
    });

    if (!response.ok) throw new Error(`GitHub returned ${response.status}`);

    const release = await response.json();
    const download = release.assets.find((asset) => asset.name.endsWith(".zip"));
    const destination = download?.browser_download_url ?? release.html_url;
    const label = `Download ${release.tag_name}`;

    for (const button of downloadButtons) {
      button.href = destination;
      button.querySelector("span").textContent = label;
    }

    releaseNote.textContent = `${release.name} is signed and notarized. Free and open source.`;
  } catch (error) {
    for (const button of downloadButtons) button.href = releaseFallback;
    releaseNote.textContent = "Latest signed and notarized release. Free and open source.";
  }
}

for (const button of document.querySelectorAll(".style-option")) {
  button.addEventListener("click", () => {
    const bubbles = button.dataset.style === "bubbles";
    document.querySelector("#chat-preview").className = `chat-preview ${bubbles ? "bubbles-preview" : "lines-preview"}`;

    for (const option of document.querySelectorAll(".style-option")) {
      const active = option === button;
      option.classList.toggle("is-active", active);
      option.setAttribute("aria-pressed", String(active));
    }
  });
}

const appearanceButton = document.querySelector("#appearance-button");
const screenshotGrid = document.querySelector(".screenshot-grid");

appearanceButton.addEventListener("click", () => {
  const dark = screenshotGrid.dataset.appearance !== "dark";
  screenshotGrid.dataset.appearance = dark ? "dark" : "light";
  appearanceButton.setAttribute("aria-pressed", String(dark));
  appearanceButton.textContent = dark ? "Show light appearance" : "Show dark appearance";
});

loadLatestRelease();
