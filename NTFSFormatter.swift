import SwiftUI

// MARK: - Modèle

struct ExternalDisk: Identifiable, Hashable {
    let id: String          // ex. "disk5"
    let name: String
    let size: Int64

    var title: String {
        "\(id) — \(name) (\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)))"
    }
}

@discardableResult
func run(_ path: String, _ args: [String]) -> (status: Int32, output: Data) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    do { try p.run() } catch { return (-1, Data()) }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, data)
}

func diskutilPlist(_ args: [String]) -> [String: Any]? {
    let r = run("/usr/sbin/diskutil", args)
    guard r.status == 0,
          let obj = try? PropertyListSerialization.propertyList(from: r.output, format: nil),
          let dict = obj as? [String: Any] else { return nil }
    return dict
}

/// Disques externes physiques uniquement : le disque interne n'est jamais proposé.
func listExternalDisks() -> [ExternalDisk] {
    guard let list = diskutilPlist(["list", "-plist", "external", "physical"]),
          let ids = list["WholeDisks"] as? [String] else { return [] }
    return ids.compactMap { id in
        guard id.range(of: "^disk[0-9]+$", options: .regularExpression) != nil,
              let info = diskutilPlist(["info", "-plist", id]),
              (info["Internal"] as? Bool) != true else { return nil }
        let name = (info["MediaName"] as? String) ?? "Disque"
        let size = (info["TotalSize"] as? NSNumber)?.int64Value ?? (info["Size"] as? NSNumber)?.int64Value ?? 0
        return ExternalDisk(id: id, name: name, size: size)
    }
}

func findMkntfs() -> String? {
    let bundled = Bundle.main.resourcePath.map { $0 + "/ntfs/bin/mkntfs" }
    return ([bundled].compactMap { $0 } + ["/opt/homebrew/sbin/mkntfs", "/usr/local/sbin/mkntfs",
     "/opt/homebrew/bin/mkntfs", "/usr/local/bin/mkntfs"])
        .first { FileManager.default.isExecutableFile(atPath: $0) }
}

/// Garde lettres, chiffres, espace, « _ » et « - » (32 caractères max) : le nom finit dans une commande shell.
func sanitizeLabel(_ s: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " _-"))
    let cleaned = String(s.unicodeScalars.filter { allowed.contains($0) && $0.isASCII })
    let trimmed = cleaned.trimmingCharacters(in: .whitespaces)
    return String((trimmed.isEmpty ? "NTFS" : trimmed).prefix(32))
}

// MARK: - Logique

final class ViewModel: ObservableObject {
    @Published var disks: [ExternalDisk] = []
    @Published var selection: String = ""
    @Published var label = "NTFS"
    @Published var log = ""
    @Published var busy = false
    @Published var mkntfsPath: String? = findMkntfs()

    var selectedDisk: ExternalDisk? { disks.first { $0.id == selection } }

    func refresh() {
        mkntfsPath = findMkntfs()
        let found = listExternalDisks()
        disks = found
        if !found.contains(where: { $0.id == selection }) { selection = found.first?.id ?? "" }
    }

    func format() {
        guard let disk = selectedDisk, let mkntfs = mkntfsPath, !busy else { return }
        // Revérification au dernier moment : le disque doit toujours être externe.
        guard listExternalDisks().contains(disk) else {
            log += "Le disque \(disk.id) a changé ou a été débranché. Rien n'a été effacé.\n"
            refresh()
            return
        }
        let name = sanitizeLabel(label)
        let d = disk.id
        let script = """
        set -e; \
        /usr/sbin/diskutil unmountDisk force /dev/\(d); \
        /usr/sbin/diskutil partitionDisk /dev/\(d) 1 GPT ExFAT TMP R; \
        /usr/sbin/diskutil unmount /dev/\(d)s2 || true; \
        '\(mkntfs)' -Q -F -L '\(name)' /dev/\(d)s2; \
        /usr/sbin/diskutil mountDisk /dev/\(d) || true
        """
        let escaped = script
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let apple = "do shell script \"\(escaped) 2>&1\" with administrator privileges"

        busy = true
        log = "Formatage de \(d) en NTFS (nom : \(name))…\n"
        DispatchQueue.global().async {
            let r = run("/usr/bin/osascript", ["-e", apple])
            let out = String(data: r.output, encoding: .utf8) ?? ""
            DispatchQueue.main.async {
                self.log += out
                self.log += r.status == 0
                    ? "\n✅ Terminé ! Le disque est en NTFS : tu peux le brancher sur un PC Windows.\n"
                    : "\n❌ Échec ou annulation (code \(r.status)).\n"
                self.busy = false
                self.refresh()
            }
        }
    }
}

// MARK: - Interface

struct ContentView: View {
    @StateObject private var vm = ViewModel()
    @State private var confirming = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Formater un disque en NTFS").font(.title2.bold())
            Text("1. Branche ton disque ou ta clé USB.   2. Choisis-le ci-dessous.   3. Clique sur Formater.")
                .foregroundStyle(.secondary)

            if vm.mkntfsPath == nil {
                Text("❌ L'outil de formatage est introuvable dans l'app. Télécharge à nouveau l'application complète.")
                    .foregroundStyle(.red)
            }

            HStack {
                Picker("Disque", selection: $vm.selection) {
                    if vm.disks.isEmpty { Text("Aucun disque externe").tag("") }
                    ForEach(vm.disks) { Text($0.title).tag($0.id) }
                }
                Button("Actualiser") { vm.refresh() }.disabled(vm.busy)
            }

            HStack {
                Text("Nom du volume")
                TextField("NTFS", text: $vm.label).frame(maxWidth: 200)
            }

            Text("⚠️ Tout le contenu du disque sélectionné sera effacé, y compris toutes ses partitions.")
                .foregroundStyle(.red)

            HStack {
                Button("Formater en NTFS…") { confirming = true }
                    .disabled(vm.selectedDisk == nil || vm.mkntfsPath == nil || vm.busy)
                if vm.busy { ProgressView().controlSize(.small) }
            }

            ScrollView {
                Text(vm.log)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .padding(8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            .frame(minHeight: 120)

            Text("macOS monte les volumes NTFS en lecture seule : pour y écrire, il faut un pilote tiers.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 440)
        .onAppear { vm.refresh() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in
            if !vm.busy { vm.refresh() }
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in
            if !vm.busy { vm.refresh() }
        }
        .confirmationDialog(
            "Effacer \(vm.selectedDisk?.title ?? "") ?",
            isPresented: $confirming, titleVisibility: .visible
        ) {
            Button("Effacer et formater en NTFS", role: .destructive) { vm.format() }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Cette action est irréversible.")
        }
    }
}

@main
struct NTFSFormatterApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
            .windowResizability(.contentMinSize)
    }
}
