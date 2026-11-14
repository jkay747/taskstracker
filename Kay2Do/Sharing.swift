import SwiftUI
import CloudKit
import CoreData

// Sharing uses Apple's own invitation screens: you pick people from Messages,
// Mail or a copied link, and they accept with their Apple ID.

#if os(iOS)
import UIKit

struct ShareBox: Identifiable {
    let id = UUID()
    let share: CKShare
    let title: String
}

struct CloudSharingSheet: UIViewControllerRepresentable {
    let box: ShareBox

    func makeCoordinator() -> Coordinator { Coordinator(title: box.title) }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: box.share, container: Persistence.shared.cloudContainer)
        controller.availablePermissions = [.allowPrivate, .allowReadWrite, .allowReadOnly]
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UICloudSharingController, context: Context) { }

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let title: String
        init(title: String) { self.title = title }

        func itemTitle(for csc: UICloudSharingController) -> String? { title }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            Persistence.shared.report(error, doing: "share this category")
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            if let share = csc.share { Persistence.shared.persist(share) }
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            if let share = csc.share { Persistence.shared.stoppedSharing(share) }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
            Persistence.shared.accept(metadata)
        }
    }

    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        Persistence.shared.accept(cloudKitShareMetadata)
    }
}
#endif

#if os(macOS)
import AppKit

enum MacSharing {
    private static let delegate = Delegate()

    static func present(_ share: CKShare) {
        let provider = NSItemProvider()
        provider.registerCloudKitShare(share, container: Persistence.shared.cloudContainer)
        guard let service = NSSharingService(named: .cloudSharing) else { return }
        service.delegate = delegate
        service.perform(withItems: [provider])
    }

    final class Delegate: NSObject, NSCloudSharingServiceDelegate {
        func sharingService(_ sharingService: NSSharingService, didSave share: CKShare) {
            Persistence.shared.persist(share)
        }

        func sharingService(_ sharingService: NSSharingService, didStopSharing share: CKShare) {
            Persistence.shared.stoppedSharing(share)
        }

        func options(for cloudKitSharingService: NSSharingService, share provider: NSItemProvider) -> NSSharingService.CloudKitOptions {
            [.allowPrivate, .allowReadWrite, .allowReadOnly]
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        Persistence.shared.accept(metadata)
    }
}
#endif

/// Set the bound category to open its invitation screen.
struct CategorySharing: ViewModifier {
    @Binding var request: TaskCategory?
    #if os(iOS)
    @State private var box: ShareBox?
    #endif

    func body(content: Content) -> some View {
        content
            .onChange(of: request) { _, category in
                guard let category = category else { return }
                request = nil
                Task { @MainActor in
                    do {
                        let share = try await Persistence.shared.share(for: category)
                        #if os(iOS)
                        box = ShareBox(share: share, title: category.name)
                        #else
                        MacSharing.present(share)
                        #endif
                    } catch {
                        Persistence.shared.report(error, doing: "share this category")
                    }
                }
            }
            #if os(iOS)
            .sheet(item: $box) { box in
                CloudSharingSheet(box: box)
                    .ignoresSafeArea()
            }
            #endif
    }
}

extension View {
    func categorySharing(_ request: Binding<TaskCategory?>) -> some View {
        modifier(CategorySharing(request: request))
    }
}
