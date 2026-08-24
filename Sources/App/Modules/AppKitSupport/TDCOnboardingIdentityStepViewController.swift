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

@objc(TDCOnboardingIdentityStepViewController)
@MainActor
public final class OnboardingIdentityStepViewController: OnboardingStepViewController {
	private var nicknameField: ValidatedTextField!
	private var realNameField: NSTextField!
	private var alternateNicknameField: ValidatedTextField!

	override public var stepTitle: String {
		LocalizedKey("TDCOnboardingWindow[id1-tt]")
	}

	override public var stepSubtitle: String {
		LocalizedKey("TDCOnboardingWindow[id1-st]")
	}

	override public var skippable: Bool {
		false
	}

	override public var preferredFirstResponder: NSView? {
		nicknameField
	}

	private func makeLabel(_ title: String) -> NSTextField {
		let label = NSTextField(labelWithString: title)
		label.alignment = .right
		label.translatesAutoresizingMaskIntoConstraints = false
		return label
	}

	override public func loadView() {
		let view = makeContentView()
		self.view = view

		let nicknameLabel = makeLabel(LocalizedKey("TDCOnboardingWindow[id1-nk]"))

		let nicknameField = ValidatedTextField()
		nicknameField.placeholderString = LocalizedKey("TDCOnboardingWindow[id1-np]")
		nicknameField.stringValueIsInvalidOnEmpty = true
		nicknameField.stringValueIsTrimmed = true
		nicknameField.stringValueUsesOnlyFirstToken = true
		nicknameField.translatesAutoresizingMaskIntoConstraints = false
		nicknameField.validationBlock = { currentValue in
			if (currentValue as NSString).isHostmaskNickname == false {
				return LocalizedKey("CommonErrors[och-j5]")
			}

			return nil
		}

		let realNameLabel = makeLabel(LocalizedKey("TDCOnboardingWindow[id1-rn]"))

		let realNameField = NSTextField(string: "")
		realNameField.placeholderString = LocalizedKey("TDCOnboardingWindow[id1-rp]")
		realNameField.translatesAutoresizingMaskIntoConstraints = false

		let alternateLabel = makeLabel(LocalizedKey("TDCOnboardingWindow[id1-an]"))

		let alternateField = ValidatedTextField()
		alternateField.placeholderString = LocalizedKey("TDCOnboardingWindow[id1-ap]")
		alternateField.stringValueIsInvalidOnEmpty = false
		alternateField.stringValueIsTrimmed = true
		alternateField.stringValueUsesOnlyFirstToken = true
		alternateField.translatesAutoresizingMaskIntoConstraints = false
		alternateField.validationBlock = { currentValue in
			if currentValue.isEmpty == false, (currentValue as NSString).isHostmaskNickname == false {
				return LocalizedKey("CommonErrors[och-j5]")
			}

			return nil
		}

		let alternateHelp = NSTextField(wrappingLabelWithString: LocalizedKey("TDCOnboardingWindow[id1-ah]"))
		alternateHelp.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
		alternateHelp.textColor = .secondaryLabelColor
		alternateHelp.translatesAutoresizingMaskIntoConstraints = false

		view.addSubview(nicknameLabel)
		view.addSubview(nicknameField)
		view.addSubview(realNameLabel)
		view.addSubview(realNameField)
		view.addSubview(alternateLabel)
		view.addSubview(alternateField)
		view.addSubview(alternateHelp)

		/* The form is centred in the content area with a fixed width, the way
		 the Setup Assistant lays out its short forms. */
		let form = NSLayoutGuide()
		view.addLayoutGuide(form)

		NSLayoutConstraint.activate([
			form.widthAnchor.constraint(equalToConstant: 440),
			form.centerXAnchor.constraint(equalTo: view.centerXAnchor),
			form.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),

			nicknameLabel.topAnchor.constraint(equalTo: form.topAnchor),
			nicknameLabel.leadingAnchor.constraint(equalTo: form.leadingAnchor),
			nicknameLabel.widthAnchor.constraint(equalToConstant: 140),
			nicknameField.leadingAnchor.constraint(equalTo: nicknameLabel.trailingAnchor, constant: 8),
			nicknameField.trailingAnchor.constraint(equalTo: form.trailingAnchor),
			nicknameField.firstBaselineAnchor.constraint(equalTo: nicknameLabel.firstBaselineAnchor),

			realNameLabel.topAnchor.constraint(equalTo: nicknameField.bottomAnchor, constant: 12),
			realNameLabel.trailingAnchor.constraint(equalTo: nicknameLabel.trailingAnchor),
			realNameLabel.widthAnchor.constraint(equalTo: nicknameLabel.widthAnchor),
			realNameField.leadingAnchor.constraint(equalTo: nicknameField.leadingAnchor),
			realNameField.trailingAnchor.constraint(equalTo: nicknameField.trailingAnchor),
			realNameField.firstBaselineAnchor.constraint(equalTo: realNameLabel.firstBaselineAnchor),

			alternateLabel.topAnchor.constraint(equalTo: realNameField.bottomAnchor, constant: 12),
			alternateLabel.trailingAnchor.constraint(equalTo: nicknameLabel.trailingAnchor),
			alternateLabel.widthAnchor.constraint(equalTo: nicknameLabel.widthAnchor),
			alternateField.leadingAnchor.constraint(equalTo: nicknameField.leadingAnchor),
			alternateField.trailingAnchor.constraint(equalTo: nicknameField.trailingAnchor),
			alternateField.firstBaselineAnchor.constraint(equalTo: alternateLabel.firstBaselineAnchor),

			alternateHelp.topAnchor.constraint(equalTo: alternateField.bottomAnchor, constant: 4),
			alternateHelp.leadingAnchor.constraint(equalTo: nicknameField.leadingAnchor),
			alternateHelp.trailingAnchor.constraint(equalTo: nicknameField.trailingAnchor),
		])

		self.nicknameField = nicknameField
		self.realNameField = realNameField
		alternateNicknameField = alternateField
	}

	override public func stepWillAppear() {
		if settings.nickname.isEmpty {
			settings.nickname = TPCPreferences.defaultNickname()
		}

		if settings.realName.isEmpty {
			settings.realName = TPCPreferences.defaultRealName()
		}

		nicknameField.stringValue = settings.nickname
		realNameField.stringValue = settings.realName
		alternateNicknameField.stringValue = settings.alternateNickname ?? ""
	}

	@objc(commitWithError:)
	override public func commit(errorDescription: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
		nicknameField.performValidation()
		alternateNicknameField.performValidation()

		if nicknameField.valueIsValid == false {
			_ = nicknameField.showValidationErrorPopover()

			if let errorDescription {
				errorDescription.pointee = nicknameField.lastValidationErrorDescription as NSString?
			}

			return false
		}

		if alternateNicknameField.valueIsValid == false {
			_ = alternateNicknameField.showValidationErrorPopover()

			if let errorDescription {
				errorDescription.pointee = alternateNicknameField.lastValidationErrorDescription as NSString?
			}

			return false
		}

		settings.nickname = nicknameField.value
		settings.realName = (realNameField.stringValue as NSString).trim

		let alternate = alternateNicknameField.value
		settings.alternateNickname = alternate.isEmpty ? nil : alternate

		return true
	}
}
