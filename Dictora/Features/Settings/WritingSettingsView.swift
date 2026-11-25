import SwiftUI

struct WritingSettingsView: View {
    @Binding var preferences: UserPreferences

    var body: some View {
        Form {
            Section {
                ForEach(WritingStyle.allCases) { style in
                    WritingStyleCard(style: style, isSelected: style == preferences.selectedWritingStyle) {
                        preferences.selectedWritingStyle = style
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }
            } header: {
                Text("Default writing style")
            }

            if preferences.selectedWritingStyle.requiresCustomInstructions {
                Section {
                    TextEditor(text: $preferences.customInstructions)
                        .frame(minHeight: 90)
                        .font(.body)
                    if !preferences.isWritingConfigurationValid {
                        Label(
                            "Custom style needs instructions, otherwise Dictora falls back to basic cleanup.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.footnote)
                        .foregroundStyle(.orange)
                    }
                } header: {
                    Text("Custom instructions")
                }
            }

            Section {
                TextEditor(text: $preferences.additionalInstructions)
                    .frame(minHeight: 90)
                    .font(.body)
                Text("Applied on top of any writing style. For example: \"Never change ticket IDs, API names, or filenames.\"")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Additional instructions")
            }

            Section {
                TextEditor(text: $preferences.customVocabulary)
                    .frame(minHeight: 70)
                    .font(.body)
                Text("Names, products and terms to spell exactly, separated by commas or new lines. Dictora already knows Claude, Anthropic and Dictora. This also helps speech recognition hear them correctly.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Names and terms")
            }

            Section {
                Picker("Strength", selection: $preferences.transformationStrength) {
                    ForEach(TransformationStrength.allCases) { strength in
                        Text(strength.displayName).tag(strength)
                    }
                }
                .pickerStyle(.segmented)

                Text(preferences.transformationStrength.shortDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Transformation strength")
            }
        }
        .formStyle(.grouped)
    }
}

#Preview {
    @Previewable @State var preferences = UserPreferences()
    WritingSettingsView(preferences: $preferences)
        .frame(width: 520, height: 700)
}
