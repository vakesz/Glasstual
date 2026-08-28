/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
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
		OnboardingStrings.Identity.title
	}

	override public var stepSubtitle: String {
		OnboardingStrings.Identity.subtitle
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

		let nicknameLabel = makeLabel(OnboardingStrings.Identity.nicknameLabel)

		let nicknameField = ValidatedTextField()
		nicknameField.placeholderString = OnboardingStrings.Identity.nicknamePlaceholder
		nicknameField.stringValueIsInvalidOnEmpty = true
		nicknameField.stringValueIsTrimmed = true
		nicknameField.stringValueUsesOnlyFirstToken = true
		nicknameField.translatesAutoresizingMaskIntoConstraints = false
		nicknameField.validationBlock = { currentValue in
			if (currentValue as NSString).isHostmaskNickname == false {
				return CommonValidationStrings.invalidNickname
			}

			return nil
		}

		let realNameLabel = makeLabel(OnboardingStrings.Identity.realNameLabel)

		let realNameField = NSTextField(string: "")
		realNameField.placeholderString = OnboardingStrings.Identity.realNamePlaceholder
		realNameField.translatesAutoresizingMaskIntoConstraints = false

		let alternateLabel = makeLabel(OnboardingStrings.Identity.alternateNicknameLabel)

		let alternateField = ValidatedTextField()
		alternateField.placeholderString = OnboardingStrings.Identity.optionalPlaceholder
		alternateField.stringValueIsInvalidOnEmpty = false
		alternateField.stringValueIsTrimmed = true
		alternateField.stringValueUsesOnlyFirstToken = true
		alternateField.translatesAutoresizingMaskIntoConstraints = false
		alternateField.validationBlock = { currentValue in
			if currentValue.isEmpty == false, (currentValue as NSString).isHostmaskNickname == false {
				return CommonValidationStrings.invalidNickname
			}

			return nil
		}

		let alternateHelp = NSTextField(
			wrappingLabelWithString: OnboardingStrings.Identity.alternateNicknameHelp
		)
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
			settings.nickname = TextualPreferences.defaultNickname()
		}

		if settings.realName.isEmpty {
			settings.realName = TextualPreferences.defaultRealName()
		}

		nicknameField.stringValue = settings.nickname
		realNameField.stringValue = settings.realName
		alternateNicknameField.stringValue = settings.alternateNickname ?? ""
	}

	override public func commit() throws {
		nicknameField.performValidation()
		alternateNicknameField.performValidation()

		for field in [nicknameField, alternateNicknameField] where field?.valueIsValid == false {
			_ = field?.showValidationErrorPopover()

			throw OnboardingStepError(field?.lastValidationErrorDescription ?? "")
		}

		settings.nickname = nicknameField.value
		settings.realName = realNameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

		let alternate = alternateNicknameField.value
		settings.alternateNickname = alternate.isEmpty ? nil : alternate
	}
}
