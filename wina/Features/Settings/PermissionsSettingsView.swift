//
//  PermissionsSettingsView.swift
//  wina
//
//  Extracted from SettingsView.swift for file length compliance
//

import AVFoundation
import Combine  // Required for ObservableObject protocol
import CoreLocation
import SwiftUI

// MARK: - Permissions Settings

struct PermissionsSettingsView: View {
    @State var settingsSearch = SettingsSearch()
    @State private var cameraStatus: AVAuthorizationStatus = .notDetermined
    @State private var microphoneStatus: AVAuthorizationStatus = .notDetermined
    @State private var locationStatus: CLAuthorizationStatus = .notDetermined
    @StateObject private var locationDelegate = LocationManagerDelegate()

    var body: some View {
        SettingsSearchList(screen: .permissions, search: $settingsSearch) {
            Section {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Changing permissions in Settings may restart the app")
                        .font(.subheadline)
                }
                .containerValue(\.settingsSearchRole, .notice)
            }

            Section {
                PermissionRow(
                    title: "Camera",
                    status: permissionText(for: cameraStatus),
                    granted: cameraStatus == .authorized
                ) {
                    requestCameraPermission()
                }
                .settingsSearchItem("camera")

                PermissionRow(
                    title: "Microphone",
                    status: permissionText(for: microphoneStatus),
                    granted: microphoneStatus == .authorized
                ) {
                    requestMicrophonePermission()
                }
                .settingsSearchItem("microphone")

                PermissionRow(
                    title: "Location",
                    status: permissionText(for: locationStatus),
                    granted: locationStatus == .authorizedWhenInUse || locationStatus == .authorizedAlways
                ) {
                    requestLocationPermission()
                }
                .settingsSearchItem("location")
            }
        }
        .navigationTitle(Text(verbatim: "Permissions"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            updatePermissionStatuses()
        }
    }

    private func updatePermissionStatuses() {
        cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        locationStatus = locationDelegate.locationManager.authorizationStatus
    }

    private func permissionText(for status: AVAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "Not Requested"
        case .restricted: return "Restricted"
        case .denied: return "Denied"
        case .authorized: return "Granted"
        @unknown default: return "Unknown"
        }
    }

    private func permissionText(for status: CLAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "Not Requested"
        case .restricted: return "Restricted"
        case .denied: return "Denied"
        case .authorizedAlways: return "Always"
        case .authorizedWhenInUse: return "When In Use"
        @unknown default: return "Unknown"
        }
    }

    private func requestCameraPermission() {
        if cameraStatus == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { _ in
                DispatchQueue.main.async {
                    cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
                }
            }
        } else {
            openSettings()
        }
    }

    private func requestMicrophonePermission() {
        if microphoneStatus == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                DispatchQueue.main.async {
                    microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
                }
            }
        } else {
            openSettings()
        }
    }

    private func requestLocationPermission() {
        if locationStatus == .notDetermined {
            locationDelegate.requestPermission { status in
                locationStatus = status
            }
        } else {
            openSettings()
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Permission Row

private struct PermissionRow: View {
    let title: String
    let status: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(status)
                .foregroundStyle(granted ? .green : .secondary)
                .font(.subheadline)
            Button {
                action()
            } label: {
                Image(systemName: granted ? "checkmark.circle.fill" : "arrow.right.circle")
                    .foregroundStyle(granted ? .green : .blue)
                    .padding(8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Location Manager Delegate

private class LocationManagerDelegate: NSObject, ObservableObject, CLLocationManagerDelegate {
    let locationManager = CLLocationManager()
    private var completion: ((CLAuthorizationStatus) -> Void)?

    override init() {
        super.init()
        locationManager.delegate = self
    }

    func requestPermission(completion: @escaping (CLAuthorizationStatus) -> Void) {
        self.completion = completion
        locationManager.requestWhenInUseAuthorization()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            self.completion?(manager.authorizationStatus)
        }
    }
}

#Preview("Permissions Settings") {
    NavigationStack {
        PermissionsSettingsView()
    }
}
