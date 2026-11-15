import SwiftUI

struct InstanceStep: View {
    let model: OnboardingModel

    @State private var instance: InstanceStepModel

    init(model: OnboardingModel) {
        self.model = model
        _instance = State(initialValue: InstanceStepModel(onboarding: model))
    }

    var body: some View {
        OnboardingStepLayout(
            symbol: "square.stack.3d.up.fill",
            title: "Pick your Minecraft",
            subtitle: "Choose a version and how to play it. You can add more instances later."
        ) {
            VStack(alignment: .leading, spacing: 22) {
                VersionRow(model: model, instance: instance)
                LoaderPicker(selection: model.progress.loader, onSelect: instance.selectLoader)
                LoaderStatus(availability: instance.loaderAvailability, loader: model.progress.loader)
                NameField(model: model, instance: instance)
            }
            .frame(maxWidth: 648)
        } actions: {
            OnboardingBackButton(model: model)
            Spacer()
            OnboardingContinueButton(action: model.goToNextStep)
                .disabled(!instance.canContinue)
        }
        .task { await instance.loadVersions() }
        .task(id: instance.loaderQuery) { await instance.checkLoader() }
    }
}

private struct VersionRow: View {
    let model: OnboardingModel
    let instance: InstanceStepModel

    var body: some View {
        HStack(spacing: 12) {
            Text("Minecraft version")
                .font(.headline)
            Spacer()
            if instance.isLoadingVersions && instance.versions.isEmpty {
                ProgressView()
                    .controlSize(.small)
            } else if let error = instance.versionsError, instance.versions.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                Button("Try Again") {
                    Task { await instance.loadVersions() }
                }
                .buttonStyle(.glass)
            } else {
                Toggle("Snapshots", isOn: Binding(
                    get: { instance.includesSnapshots },
                    set: { newValue in Task { await instance.setIncludesSnapshots(newValue) } }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                Picker("Minecraft version", selection: Binding(
                    get: { model.progress.minecraftVersion ?? "" },
                    set: instance.selectMinecraftVersion
                )) {
                    ForEach(instance.versions) { version in
                        Text(version.type == "release" ? version.id : "\(version.id) (snapshot)")
                            .tag(version.id)
                    }
                }
                .labelsHidden()
                .frame(width: 200)
            }
        }
    }
}

private struct LoaderOption: Identifiable {
    let loader: ModLoader?
    let symbol: String
    let detail: LocalizedStringKey

    var id: String {
        loader?.rawValue ?? "vanilla"
    }

    var title: String {
        loader?.displayName ?? "Vanilla"
    }

    static let all = [
        LoaderOption(loader: nil, symbol: "cube.fill", detail: "The game as Mojang ships it"),
        LoaderOption(loader: .fabric, symbol: "bolt.fill", detail: "Light and quick to update"),
        LoaderOption(loader: .quilt, symbol: "square.grid.2x2.fill", detail: "A fork of Fabric"),
        LoaderOption(loader: .forge, symbol: "hammer.fill", detail: "The classic loader for big mods"),
        LoaderOption(loader: .neoForge, symbol: "flame.fill", detail: "A community fork of Forge"),
    ]
}

private struct LoaderPicker: View {
    let selection: ModLoader?
    let onSelect: (ModLoader?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Mod loader")
                .font(.headline)
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    ForEach(LoaderOption.all) { option in
                        LoaderTile(option: option, isSelected: option.loader == selection) {
                            onSelect(option.loader)
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct LoaderTile: View {
    let option: LoaderOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: option.symbol)
                        .font(.title3)
                        .foregroundStyle(isSelected ? AnyShapeStyle(OnboardingPalette.amber.gradient) : AnyShapeStyle(.secondary))
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(OnboardingPalette.amber)
                        .opacity(isSelected ? 1 : 0)
                        .scaleEffect(isSelected ? 1 : 0.6)
                }
                Text(option.title)
                    .font(.headline)
                Text(option.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(12)
            .contentShape(.rect(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .glassEffect(
            isSelected ? .regular.tint(OnboardingPalette.amber.opacity(0.28)).interactive() : .regular.interactive(),
            in: .rect(cornerRadius: 18)
        )
        .animation(.spring(duration: 0.3, bounce: 0.25), value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct LoaderStatus: View {
    let availability: InstanceStepModel.LoaderAvailability
    let loader: ModLoader?

    var body: some View {
        Group {
            switch availability {
            case .notNeeded:
                Label("No mod loader. Mods will not load in this instance.", systemImage: "info.circle")
                    .foregroundStyle(.secondary)
            case .checking:
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Checking \(loader?.displayName ?? "") for this version")
                }
                .foregroundStyle(.secondary)
            case .available(let version):
                Label("Installs \(loader?.displayName ?? "") \(version), the recommended version.", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            case .unavailable:
                Label("\(loader?.displayName ?? "This loader") has no version for this Minecraft version. Pick another version or loader.", systemImage: "xmark.circle")
                    .foregroundStyle(.orange)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
        .animation(.smooth(duration: 0.25), value: availability)
    }
}

private struct NameField: View {
    let model: OnboardingModel
    let instance: InstanceStepModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Instance name")
                .font(.headline)
            TextField(instance.defaultInstanceName, text: Binding(
                get: { model.progress.instanceName ?? "" },
                set: instance.setInstanceName
            ))
            .textFieldStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .glassEffect(.regular, in: .capsule)
            if !instance.isInstanceNameUsable {
                Text("Use a name with at least one letter or digit.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}

#Preview {
    InstanceStep(model: .preview())
        .frame(width: 760, height: 620)
        .background(OnboardingBackground())
}
