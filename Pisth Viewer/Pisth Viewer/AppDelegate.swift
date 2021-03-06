// This source file is part of the https://github.com/ColdGrub1384/Pisth open source project
//
// Copyright (c) 2017 - 2018 Adrian Labbé
// Licensed under Apache License v2.0
//
// See https://raw.githubusercontent.com/ColdGrub1384/Pisth/master/LICENSE for license information

import Cocoa
import WebKit
import MultipeerConnectivity
import Pisth_Shared
import Pisth_Terminal

/// Pisth Viewer app for macOS.
/// This app is used to view a terminal opened from Pisth in near iOS device.
/// This app and Pisth use Multipeer connectivity framework.
/// Content received in Pisth for iOS is sent to this app.
@NSApplicationMain
class PisthViewerAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSOutlineViewDataSource, NSOutlineViewDelegate, WKNavigationDelegate, MCSessionDelegate, MCNearbyServiceBrowserDelegate {
    
    /// Last received theme name.
    var lastReceivedThemeName = ""
    
    /// Show licenses in a web browser.
    @IBAction func showLicenses(_ sender: Any) {
        NSWorkspace.shared.open(URL(string: "https://pisth.github.io/Licenses")!)
    }
    
    /// Paste text.
    ///
    /// - Parameters:
    ///     - sender: Sender object.
    @IBAction func pasteText(_ sender: Any) {
        let string = NSPasteboard.general.string(forType: .string) ?? ""
        guard let data = string.data(using: .utf8) else {
            return
        }
        try? mcSession?.send(data, toPeers: mcSession?.connectedPeers ?? [], with: .unreliable)
    }
    
    
    // MARK: - Show nearby devices
    
    /// Nearby devices.
    ///
    /// First item is always a peer id with display name `"Devices\n"` to show it as header, this item isn't selectable.
    var devices = [MCPeerID(displayName: "Devices\n")]
    
    /// Main and unique window.
    @IBOutlet weak var window: NSWindow!
    
    /// View displaying near devices.
    @IBOutlet weak var outlineView: NSOutlineView!
    
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        return devices.count
    }
    
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        return false
    }
    
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        return devices[index]
    }
    
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let peerID = item as? MCPeerID else {
            return nil
        }
        
        if peerID == devices[0] {
            let header = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("HeaderCell"), owner: self)
            return header
        } else {
            guard let cell = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("DataCell"), owner: self) else {
                return nil
            }
            
            for view in cell.subviews {
                if let textField = view as? NSTextField {
                    textField.stringValue = peerID.displayName
                }
            }
            
            return cell
        }
    }
    
    func outlineViewSelectionDidChange(_ notification: Notification) {
        print(outlineView.selectedRow)
        mcNearbyServiceBrowser.invitePeer(devices[outlineView.selectedRow], to: mcSession, withContext: nil, timeout: 10)
    }
    
    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        return ((item as? MCPeerID) != devices[0])
    }
    
    
    // MARK: - Connectivity
    
    /// Peer ID used for the Multipeer connectivity session.
    var peerID: MCPeerID!
    
    /// Multipeer connectivity session used to receive and send data to peers.
    var mcSession: MCSession!
    
    /// Multipeer connectivity browser used to browser nearby devices.
    var mcNearbyServiceBrowser: MCNearbyServiceBrowser!
    
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        print("Changed state!")
        
        if state == .connected {
            DispatchQueue.main.async {
                self.clearTerminal()
            }
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        
        NSKeyedUnarchiver.setClass(TerminalInfo.self, forClassName: "TerminalInfo")
        
        if let info = NSKeyedUnarchiver.unarchiveObject(with: data) as? TerminalInfo {
            
            let theme = TerminalTheme.themes[info.themeName] ?? ProTheme()
            
            DispatchQueue.main.async {
                
                let width = CGFloat(info.terminalSize[0])
                let height = CGFloat(info.terminalSize[1])+30
                self.webView.frame.size = CGSize(width: width, height: height)
                self.outlineView.superview?.superview?.frame.size.height = self.webView.frame.height
                self.window.setFrame(CGRect(origin: self.window.frame.origin, size: CGSize(width: self.webView.frame.width+self.outlineView.frame.width, height: self.webView.frame.height+20)), display: false)
                self.webView.frame.origin = CGPoint(x: self.outlineView.frame.width, y: 0)
                self.outlineView.superview?.superview?.frame.origin.y = 0
                
                self.webView.evaluateJavaScript("fit(term)", completionHandler: nil)
                if info.themeName != self.lastReceivedThemeName {
                    self.webView.evaluateJavaScript("term.setOption('theme', \(theme.javascriptValue))", completionHandler: nil)
                    self.lastReceivedThemeName = info.themeName
                }
                self.webView.evaluateJavaScript("document.body.style.backgroundColor = '\(theme.backgroundColor?.hexString ?? "#000000")'", completionHandler: nil)
                self.webView.evaluateJavaScript("term.write(\(info.message.javaScriptEscapedString))", completionHandler: nil)
            }
        }
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        print("Received stream")
    }
    
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        print("Start receiving resource")
    }
    
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        print("Finish receiving resource")
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        devices.append(peerID)
        outlineView.reloadData()
        print(devices)
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        if let index = devices.index(of: peerID) {
            devices.remove(at: index)
        }
        outlineView.reloadData()
        print(devices)
    }
    
    
    // MARK: - Terminal
    
    /// Show help message.
    func showHelpMessage() {
        webView.evaluateJavaScript("term.write('Open a terminal from Pisth in your iOS device.')", completionHandler: nil)
    }
    
    /// Clear terminal.
    func clearTerminal() {
        webView.evaluateJavaScript("term.write('\(Keys.esc)[2J\(Keys.esc)[H\')", completionHandler: nil)
    }
    
    /// Web view used to display terminal.
    @IBOutlet weak var webView: WKWebView!
    
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        showHelpMessage()
        webView.evaluateJavaScript("document.body.style.backgroundColor = '#000000'", completionHandler: nil)
        webView.evaluateJavaScript("fit(term)", completionHandler: nil)
    }
    
    
    // MARK: - App delegate
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        
        guard let terminal = Bundle.terminal.url(forResource: "terminal", withExtension: "html") else {
            return
        }
        webView.loadFileURL(terminal, allowingReadAccessTo: terminal.deletingLastPathComponent())
        
        // Connectivity
        peerID = MCPeerID(displayName: Host.current().name ?? "Mac")
        mcSession = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .none)
        mcSession.delegate = self
        mcNearbyServiceBrowser = MCNearbyServiceBrowser(peer: peerID, serviceType: "terminal")
        mcNearbyServiceBrowser.delegate = self
        mcNearbyServiceBrowser.startBrowsingForPeers()
        
        // Check for new version
        URLSession.shared.dataTask(with: URL(string:"https://pisth.github.io/PisthViewer/NEW_VERSION")!) { (data, _, _) in
            
            guard let data = data else {
                return
            }
            
            if let str = String(data: data, encoding: .utf8) {
                if (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) != str.components(separatedBy: "\n\n")[0] {
                    
                    DispatchQueue.main.async {
                        let alert = NSAlert()
                        alert.messageText = "New version available"
                        alert.informativeText = str
                        
                        alert.addButton(withTitle: "Update")
                        alert.addButton(withTitle: "Don't update")
                        
                        alert.alertStyle = .informational
                        
                        if alert.runModal() == .alertFirstButtonReturn {
                            NSWorkspace.shared.open(URL(string: "https://pisth.github.io/PisthViewer")!)
                        }
                        
                        alert.beginSheetModal(for: self.window, completionHandler: nil)
                    }
                }
            }
            }.resume()
        
        // Keys handling
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { (event) in
            
            guard var character = event.characters else {
                return nil
            }
            
            guard let utf16view = event.charactersIgnoringModifiers?.utf16 else {
                return nil
            }
            
            let key = Int(utf16view[utf16view.startIndex])
            
            switch key {
                
            // Arrow keys
            case NSEvent.SpecialKey.upArrow.rawValue:
                character = Keys.arrowUp
            case NSEvent.SpecialKey.downArrow.rawValue:
                character = Keys.arrowDown
            case NSEvent.SpecialKey.leftArrow.rawValue:
                character = Keys.arrowLeft
            case NSEvent.SpecialKey.rightArrow.rawValue:
                character = Keys.arrowRight
                
            // Function Keys
            case NSEvent.SpecialKey.f1.rawValue:
                character = Keys.f1
            case NSEvent.SpecialKey.f2.rawValue:
                character = Keys.f2
            case NSEvent.SpecialKey.f3.rawValue:
                character = Keys.f3
            case NSEvent.SpecialKey.f4.rawValue:
                character = Keys.f4
            case NSEvent.SpecialKey.f5.rawValue:
                character = Keys.f5
            case NSEvent.SpecialKey.f6.rawValue:
                character = Keys.f6
            case NSEvent.SpecialKey.f7.rawValue:
                character = Keys.f7
            case NSEvent.SpecialKey.f8.rawValue:
                character = Keys.f8
            case NSEvent.SpecialKey.f2.rawValue:
                character = Keys.f2
            case NSEvent.SpecialKey.f9.rawValue:
                character = Keys.f9
            case NSEvent.SpecialKey.f10.rawValue:
                character = Keys.f10
            case NSEvent.SpecialKey.f11.rawValue:
                character = Keys.f11
            default:
                break
            }
            
            guard let data = character.data(using: .utf8) else {
                return nil
            }
            
            if !event.modifierFlags.contains(.command) {
                try? self.mcSession.send(data, toPeers: self.mcSession.connectedPeers, with: .unreliable)
            }
            
            return event
        }
    }
    
    
    // MARK: - Window delegate
    
    func windowWillClose(_ notification: Notification) {
        exit(0)
    }
}


