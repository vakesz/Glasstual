/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit

@objc(TDCOnboardingAppearanceStepViewController)
@MainActor
public final class OnboardingAppearanceStepViewController: OnboardingStepViewController {
	private var bubblesPreview: OnboardingStylePreviewView!
	private var linesPreview: OnboardingStylePreviewView!
	private var textSizeControl: NSSegmentedControl!
	private var appearanceControl: NSSegmentedControl!

	override public var stepTitle: String {
		OnboardingStrings.Appearance.title
	}

	override public var stepSubtitle: String {
		OnboardingStrings.Appearance.subtitle
	}

	override public func loadView() {
		let view = makeContentView()
		self.view = view

		let bubblesPreview = OnboardingStylePreviewView()
		bubblesPreview.styleName = "Bubbles"
		bubblesPreview.styleTitle = OnboardingStrings.Appearance.bubblesTitle
		bubblesPreview.styleDescription = OnboardingStrings.Appearance.bubblesDescription
		bubblesPreview.target = self
		bubblesPreview.action = #selector(previewSelected(_:))
		bubblesPreview.translatesAutoresizingMaskIntoConstraints = false

		let linesPreview = OnboardingStylePreviewView()
		linesPreview.styleName = "Lines"
		linesPreview.styleTitle = OnboardingStrings.Appearance.linesTitle
		linesPreview.styleDescription = OnboardingStrings.Appearance.linesDescription
		linesPreview.target = self
		linesPreview.action = #selector(previewSelected(_:))
		linesPreview.translatesAutoresizingMaskIntoConstraints = false

		let previewStack = NSStackView(views: [bubblesPreview, linesPreview])
		previewStack.orientation = .horizontal
		previewStack.distribution = .fillEqually
		previewStack.spacing = 20
		previewStack.translatesAutoresizingMaskIntoConstraints = false
		previewStack.setAccessibilityLabel(OnboardingStrings.Appearance.previewAccessibilityLabel)

		let textSizeLabel = NSTextField(labelWithString: OnboardingStrings.Appearance.textSizeLabel)
		textSizeLabel.alignment = .right
		textSizeLabel.translatesAutoresizingMaskIntoConstraints = false

		let textSizeControl = NSSegmentedControl(
			labels: OnboardingStrings.Appearance.textSizeTitles,
			trackingMode: .selectOne,
			target: self,
			action: #selector(textSizeChanged(_:))
		)
		textSizeControl.translatesAutoresizingMaskIntoConstraints = false

		let appearanceLabel = NSTextField(labelWithString: OnboardingStrings.Appearance.interfaceStyleLabel)
		appearanceLabel.alignment = .right
		appearanceLabel.translatesAutoresizingMaskIntoConstraints = false

		let appearanceControl = NSSegmentedControl(
			labels: OnboardingStrings.Appearance.interfaceStyleTitles,
			trackingMode: .selectOne,
			target: self,
			action: #selector(appearanceChanged(_:))
		)
		appearanceControl.translatesAutoresizingMaskIntoConstraints = false

		view.addSubview(previewStack)
		view.addSubview(textSizeLabel)
		view.addSubview(textSizeControl)
		view.addSubview(appearanceLabel)
		view.addSubview(appearanceControl)

		NSLayoutConstraint.activate([
			previewStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
			previewStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
			previewStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

			textSizeControl.topAnchor.constraint(equalTo: previewStack.bottomAnchor, constant: 24),
			textSizeControl.centerXAnchor.constraint(equalTo: view.centerXAnchor, constant: 60),
			textSizeLabel.trailingAnchor.constraint(equalTo: textSizeControl.leadingAnchor, constant: -8),
			textSizeLabel.centerYAnchor.constraint(equalTo: textSizeControl.centerYAnchor),

			appearanceControl.topAnchor.constraint(equalTo: textSizeControl.bottomAnchor, constant: 12),
			appearanceControl.leadingAnchor.constraint(equalTo: textSizeControl.leadingAnchor),
			appearanceLabel.trailingAnchor.constraint(equalTo: textSizeLabel.trailingAnchor),
			appearanceLabel.centerYAnchor.constraint(equalTo: appearanceControl.centerYAnchor),
		])

		self.bubblesPreview = bubblesPreview
		self.linesPreview = linesPreview
		self.textSizeControl = textSizeControl
		self.appearanceControl = appearanceControl
	}

	override public func stepWillAppear() {
		updatePreviewSelection()

		textSizeControl.selectedSegment = Int(settings.textSize.rawValue)

		let fontSize = OnboardingSettings.fontSize(for: settings.textSize)
		bubblesPreview.messageFontSize = fontSize
		linesPreview.messageFontSize = fontSize

		appearanceControl.selectedSegment = Int(settings.appearance.rawValue)
	}

	private func updatePreviewSelection() {
		let bubbles = settings.styleName == "Bubbles"
		bubblesPreview.selected = bubbles
		linesPreview.selected = bubbles == false
	}

	@objc private func previewSelected(_ sender: OnboardingStylePreviewView) {
		settings.styleName = sender.styleName
		updatePreviewSelection()
	}

	@objc private func textSizeChanged(_ sender: NSSegmentedControl) {
		let textSize = TDCOnboardingTextSize(rawValue: UInt(sender.selectedSegment)) ?? .medium
		settings.textSize = textSize

		let fontSize = OnboardingSettings.fontSize(for: textSize)
		bubblesPreview.messageFontSize = fontSize
		linesPreview.messageFontSize = fontSize
	}

	@objc private func appearanceChanged(_ sender: NSSegmentedControl) {
		settings.appearance = TXPreferredAppearance(rawValue: UInt(sender.selectedSegment)) ?? .inherited
	}
}
