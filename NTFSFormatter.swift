import SwiftUI

// MARK: - Model

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

/// External physical disks only: the internal disk is never offered.
func listExternalDisks() -> [ExternalDisk] {
    guard let list = diskutilPlist(["list", "-plist", "external", "physical"]),
          let ids = list["WholeDisks"] as? [String] else { return [] }
    return ids.compactMap { id in
        guard id.range(of: "^disk[0-9]+$", options: .regularExpression) != nil,
              let info = diskutilPlist(["info", "-plist", id]),
              (info["Internal"] as? Bool) != true else { return nil }
        let name = (info["MediaName"] as? String) ?? "Disk"
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

/// Keeps letters, digits, space, "_" and "-" (32 characters max): the name ends up in a shell command.
func sanitizeLabel(_ s: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " _-"))
    let cleaned = String(s.unicodeScalars.filter { allowed.contains($0) && $0.isASCII })
    let trimmed = cleaned.trimmingCharacters(in: .whitespaces)
    return String((trimmed.isEmpty ? "NTFS" : trimmed).prefix(32))
}

// MARK: - Logic

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
        // Last-moment re-check: the disk must still be external.
        guard listExternalDisks().contains(disk) else {
            log += "Disk \(disk.id) has changed or was unplugged. Nothing was erased.\n"
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
        log = "Formatting \(d) as NTFS (name: \(name))…\n"
        DispatchQueue.global().async {
            let r = run("/usr/bin/osascript", ["-e", apple])
            let out = String(data: r.output, encoding: .utf8) ?? ""
            DispatchQueue.main.async {
                self.log += out
                self.log += r.status == 0
                    ? "\n✅ Done! The disk is now NTFS: you can plug it into a Windows PC.\n"
                    : "\n❌ Failed or cancelled (code \(r.status)).\n"
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
            Text("Format a disk as NTFS").font(.title2.bold())
            Text("1. Plug in your disk or USB drive.   2. Select it below.   3. Click Format.")
                .foregroundStyle(.secondary)

            if vm.mkntfsPath == nil {
                Text("❌ The formatting tool is missing from the app. Please download the full app again.")
                    .foregroundStyle(.red)
            }

            HStack {
                Picker("Disk", selection: $vm.selection) {
                    if vm.disks.isEmpty { Text("No external disk").tag("") }
                    ForEach(vm.disks) { Text($0.title).tag($0.id) }
                }
                Button("Refresh") { vm.refresh() }.disabled(vm.busy)
            }

            HStack {
                Text("Volume name")
                TextField("NTFS", text: $vm.label).frame(maxWidth: 200)
            }

            Text("⚠️ Everything on the selected disk will be erased, including all its partitions.")
                .foregroundStyle(.red)

            HStack {
                Button("Format as NTFS…") { confirming = true }
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

            Text("macOS mounts NTFS volumes read-only: writing to them needs a third-party driver.")
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
            "Erase \(vm.selectedDisk?.title ?? "")?",
            isPresented: $confirming, titleVisibility: .visible
        ) {
            Button("Erase and format as NTFS", role: .destructive) { vm.format() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
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
