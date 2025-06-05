//  ContentView.swift
//  CALAPP
//  (Restored)

import SwiftUI
import Foundation

// --- Models ---
struct Message: Identifiable, Codable {
    var id: UUID
    let text: String
    let isCurrentUser: Bool
    let timestamp: Date
    init(id: UUID = UUID(), text: String, isCurrentUser: Bool, timestamp: Date = Date()) {
        self.id = id
        self.text = text
        self.isCurrentUser = isCurrentUser
        self.timestamp = timestamp
    }
}

struct Conversation: Identifiable, Codable {
    var id: UUID
    var name: String
    var messages: [MessageTree]
    let createdAt: Date
    init(id: UUID = UUID(), name: String, messages: [MessageTree] = [], createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.messages = messages
        self.createdAt = createdAt
    }
    var lastMessagePreview: String {
        guard let lastMessage = messages.last?.allMessages.last else { return "No messages" }
        return lastMessage.text.prefix(50) + (lastMessage.text.count > 50 ? "..." : "")
    }
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }
}

struct AISettings: Codable {
    var systemPrompt: String
    var temperature: Double
    var maxTokens: Int
    var topP: Double
    var topK: Int
    var frequencyPenalty: Double
    var presencePenalty: Double
    var model: String
    static let `default` = AISettings(
        systemPrompt: "You are a helpful, intelligent, and creative AI assistant.",
        temperature: 0.8,
        maxTokens: 2000,
        topP: 0.9,
        topK: 40,
        frequencyPenalty: 0.1,
        presencePenalty: 0.1,
        model: "dolphin-2.9.4-llama3.1-8b"
    )
}

// --- MessageTree for branching edits ---
struct MessageBranch: Identifiable, Codable {
    var id: UUID
    var parentMessageId: UUID
    var aiMessage: Message
    var timestamp: Date
    
    init(id: UUID = UUID(), parentMessageId: UUID, aiMessage: Message, timestamp: Date = Date()) {
        self.id = id
        self.parentMessageId = parentMessageId
        self.aiMessage = aiMessage
        self.timestamp = timestamp
    }
}

struct MessageTree: Identifiable, Codable {
    var id: UUID
    var text: String
    var isCurrentUser: Bool
    var timestamp: Date
    var branches: [MessageBranch]
    var selectedBranchId: UUID?
    var parentTreeId: UUID?
    var childTreeIds: [UUID]
    
    init(id: UUID = UUID(), text: String, isCurrentUser: Bool, timestamp: Date = Date(), branches: [MessageBranch] = [], selectedBranchId: UUID? = nil, parentTreeId: UUID? = nil, childTreeIds: [UUID] = []) {
        self.id = id
        self.text = text
        self.isCurrentUser = isCurrentUser
        self.timestamp = timestamp
        self.branches = branches
        self.selectedBranchId = selectedBranchId
        self.parentTreeId = parentTreeId
        self.childTreeIds = childTreeIds
    }
    
    var currentBranch: MessageBranch? {
        guard let selectedId = selectedBranchId else { return nil }
        return branches.first { $0.id == selectedId }
    }
    
    var allMessages: [Message] {
        var messages = [Message(id: id, text: text, isCurrentUser: isCurrentUser, timestamp: timestamp)]
        if let branch = currentBranch {
            messages.append(branch.aiMessage)
        }
        return messages
    }
}

struct MessageVersion: Identifiable, Codable {
    var id: UUID
    var text: String
    var timestamp: Date
    var editedAt: Date
    init(id: UUID = UUID(), text: String, timestamp: Date = Date(), editedAt: Date = Date()) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
        self.editedAt = editedAt
    }
}

// --- ViewModel ---
class ChatViewModel: ObservableObject {
    @Published var conversations: [UUID: Conversation] = [:]
    @Published var conversationNames: [UUID: String] = [:]
    @Published var aiSettings: AISettings = .default
    @Published var selectedConversationId: UUID?
    @Published var editingConversationNameId: UUID?
    @Published var editingMessageId: UUID?
    @Published var isTyping: Bool = false

    var selectedConversation: Conversation? {
        guard let id = selectedConversationId else { return nil }
        return conversations[id]
    }

    init() {
        let defaultConversation = Conversation(name: "General Chat")
        conversations[defaultConversation.id] = defaultConversation
        selectedConversationId = defaultConversation.id
    }

    func createNewConversation(name: String, autoRename: Bool = true) {
        let newConversation = Conversation(name: name)
        conversations.insert(newConversation, forKey: newConversation.id)
        selectedConversationId = newConversation.id
        if autoRename {
            editingConversationNameId = newConversation.id
        }
    }
    func deleteConversation(id: UUID) {
        conversations.removeValue(forKey: id)
        if selectedConversationId == id {
            selectedConversationId = conversations.first?.key
        }
    }
    func renameConversation(id: UUID, newName: String) {
        if let conversation = conversations[id] {
            conversation.name = newName
            conversations.insert(conversation, forKey: id)
        }
        editingConversationNameId = nil
    }
    func addMessage(_ message: Message, to conversationId: UUID) {
        let newTree = MessageTree(text: message.text, isCurrentUser: message.isCurrentUser)
        if var conversation = conversations[conversationId] {
            if let lastTree = conversation.last {
                newTree.parentTreeId = lastTree.id
                conversation[conversation.count - 1].childTreeIds.append(newTree.id)
            }
            conversation.append(newTree)
            conversations.insert(conversation, forKey: conversationId)
            updateConversationName(conversationId)
        } else {
            conversations.insert(conversation, forKey: conversationId)
        }
    }
    func getMessages(for conversationId: UUID) -> [MessageTree] {
        return conversations[conversationId] ?? []
    }
    func getConversationName(for conversationId: UUID) -> String {
        return conversationNames[conversationId] ?? "Unknown"
    }
    func editMessage(conversationId: UUID, messageId: UUID, newText: String) {
        guard var conversation = conversations[conversationId] else { return }
        guard let mIdx = conversation.firstIndex(where: { $0.id == messageId }) else { return }
        let newMessageVersion = MessageVersion(text: newText, timestamp: Date())
        if conversation[mIdx].branches.isEmpty {
            let originalVersion = MessageVersion(
                text: conversation[mIdx].text,
                timestamp: conversation[mIdx].timestamp,
                editedAt: conversation[mIdx].timestamp
            )
            conversation[mIdx].branches = [MessageBranch(parentMessageId: messageId, aiMessage: conversation[mIdx].currentBranch!.aiMessage, timestamp: conversation[mIdx].timestamp)]
        }
        conversation[mIdx].branches.append(MessageBranch(parentMessageId: messageId, aiMessage: Message(id: UUID(), text: newText, isCurrentUser: conversation[mIdx].isCurrentUser, timestamp: Date())))
        conversation[mIdx].selectedBranchId = conversation[mIdx].branches.last!.id
        removeSubsequentMessages(conversationId: conversationId, afterMessageIndex: mIdx)
        editingMessageId = nil
    }
    func removeSubsequentMessages(conversationId: UUID, afterMessageIndex: Int) {
        guard var conversation = conversations[conversationId] else { return }
        let keepUpTo = afterMessageIndex + 1
        if conversation.count > keepUpTo {
            conversation.removeSubrange(keepUpTo...)
        }
        conversations.insert(conversation, forKey: conversationId)
    }
    func selectMessageBranch(conversationId: UUID, messageId: UUID, branchIdx: Int) {
        guard var conversation = conversations[conversationId] else { return }
        guard let mIdx = conversation.firstIndex(where: { $0.id == messageId }) else { return }
        conversation[mIdx].selectedBranchId = conversation[mIdx].branches[branchIdx].id
        conversations.insert(conversation, forKey: conversationId)
    }
    func addAIResponse(to conversationId: UUID, messageId: UUID, aiMessage: Message) {
        guard var conversation = conversations[conversationId] else { return }
        guard let mIdx = conversation.firstIndex(where: { $0.id == messageId }) else { return }
        let newBranch = MessageBranch(parentMessageId: messageId, aiMessage: aiMessage, timestamp: Date())
        conversation[mIdx].branches.append(newBranch)
        conversation[mIdx].selectedBranchId = newBranch.id
        conversations[conversationId] = conversation
        let allMessages = conversation.flatMap { $0.allMessages }
        if allMessages.count >= 2 && conversation.name.contains("New Chat") {
            generateContextualTitle(for: conversationId)
        }
    }
    func generateContextualTitle(for conversationId: UUID) {
        guard let conversation = conversations[conversationId] else { return }
        
        // Only update name if we have enough messages for context
        if conversation.count >= 2 {
            let messages = conversation.prefix(2).map { $0.text }
            let context = messages.joined(separator: " ")
            
            // Call AI to generate a contextual name
            guard let url = URL(string: "http://127.0.0.1:1234/v1/chat/completions") else { return }
            
            let requestBody: [String: Any] = [
                "model": aiSettings.model,
                "messages": [
                    [
                        "role": "system",
                        "content": "Generate a short, descriptive title (max 5 words) for a conversation based on these messages. The title should capture the main topic or purpose."
                    ],
                    [
                        "role": "user",
                        "content": context
                    ]
                ],
                "temperature": aiSettings.temperature,
                "max_tokens": 20
            ]
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            } catch {
                print("Failed to encode request: \(error)")
                return
            }
            
            URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let choices = json["choices"] as? [[String: Any]],
                      let firstChoice = choices.first,
                      let message = firstChoice["message"] as? [String: Any],
                      let content = message["content"] as? String else {
                    return
                }
                
                DispatchQueue.main.async {
                    self?.conversationNames[conversationId] = content.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }.resume()
        }
    }
    func selectBranch(conversationId: UUID, messageId: UUID, branchId: UUID) {
        guard var conversation = conversations[conversationId] else { return }
        guard let mIdx = conversation.firstIndex(where: { $0.id == messageId }) else { return }
        conversation[mIdx].selectedBranchId = branchId
        conversations.insert(conversation, forKey: conversationId)
    }
    func saveSettings() {}
    func loadSettings() {}
    func resetSettingsToDefault() { aiSettings = .default }
    private func updateConversationName(_ conversationId: UUID) {
        guard let conversation = conversations[conversationId] else { return }
        
        // Only update name if we have enough messages for context
        if conversation.count >= 2 {
            let messages = conversation.prefix(2).map { $0.text }
            let context = messages.joined(separator: " ")
            
            // Call AI to generate a contextual name
            guard let url = URL(string: "http://127.0.0.1:1234/v1/chat/completions") else { return }
            
            let requestBody: [String: Any] = [
                "model": aiSettings.model,
                "messages": [
                    [
                        "role": "system",
                        "content": "Generate a short, descriptive title (max 5 words) for a conversation based on these messages. The title should capture the main topic or purpose."
                    ],
                    [
                        "role": "user",
                        "content": context
                    ]
                ],
                "temperature": aiSettings.temperature,
                "max_tokens": 20
            ]
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            } catch {
                print("Failed to encode request: \(error)")
                return
            }
            
            URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let choices = json["choices"] as? [[String: Any]],
                      let firstChoice = choices.first,
                      let message = firstChoice["message"] as? [String: Any],
                      let content = message["content"] as? String else {
                    return
                }
                
                DispatchQueue.main.async {
                    self?.conversationNames[conversationId] = content.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }.resume()
        }
    }
    func addBranch(to conversationId: UUID, messageId: UUID, aiMessage: Message) {
        DispatchQueue.main.async { [weak self] in
            guard var conversation = self?.conversations[conversationId],
                  let index = conversation.firstIndex(where: { $0.id == messageId }) else { return }
            self?.isTyping = true
            let newBranch = MessageBranch(parentMessageId: messageId, aiMessage: aiMessage)
            conversation[index].branches.append(newBranch)
            conversation[index].selectedBranchId = newBranch.id
            // Create a new branch in the timeline
            let newTree = MessageTree(text: aiMessage.text, isCurrentUser: false, timestamp: aiMessage.timestamp)
            newTree.parentTreeId = messageId
            conversation[index].childTreeIds.append(newTree.id)
            self?.conversations[conversationId] = conversation
            self?.isTyping = false
        }
    }
}

// --- Main ContentView ---
struct ContentView: View {
    @StateObject var viewModel = ChatViewModel()
    @State private var selectedConversationId: UUID? = nil
    var body: some View {
        NavigationSplitView {
            SidebarView(viewModel: viewModel, selectedConversationId: $selectedConversationId)
                .background(.ultraThinMaterial)
        } detail: {
            if let conversationId = selectedConversationId {
                ChatPanelView(conversationId: conversationId, viewModel: viewModel)
                    .background(.ultraThinMaterial)
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "message")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    Text("Select a conversation")
                        .font(.title2)
                        .fontWeight(.medium)
                    Text("Choose a chat from the sidebar to start messaging")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.ultraThinMaterial)
            }
        }
        .onAppear {
            if selectedConversationId == nil {
                selectedConversationId = viewModel.conversations.first?.key
            }
        }
    }
}

// --- SidebarView ---
struct SidebarView: View {
    @ObservedObject var viewModel: ChatViewModel
    @Binding var selectedConversationId: UUID?
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Chats")
                    .font(.title3)
                    .fontWeight(.bold)
                Spacer()
                Button(action: {
                    viewModel.createNewConversation(name: "New Chat")
                    selectedConversationId = viewModel.conversations.first?.key
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.blue)
                        .padding(6)
                        .background(Color.blue.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Divider().opacity(0.2)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(viewModel.conversations.map { $0.value }) { conversation in
                        ConversationRowView(conversation: conversation, viewModel: viewModel, selectedConversationId: $selectedConversationId)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .frame(minWidth: 260, maxWidth: 320)
        .background(.ultraThinMaterial)
    }
}

struct ConversationRowView: View {
    let conversation: Conversation
    @ObservedObject var viewModel: ChatViewModel
    @State private var newName = ""
    @FocusState private var isFocused: Bool
    @Binding var selectedConversationId: UUID?
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 20)
            HStack {
                if viewModel.editingConversationNameId == conversation.id {
                    TextField("Conversation name", text: Binding(
                        get: { newName.isEmpty ? conversation.name : newName },
                        set: { newName = $0 }
                    ), onCommit: {
                        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            viewModel.renameConversation(id: conversation.id, newName: trimmed)
                        }
                        newName = ""
                    })
                    .font(.system(size: 14, weight: .medium))
                    .focused($isFocused)
                    .onAppear { isFocused = true }
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(.thinMaterial)
                    .cornerRadius(6)
                } else {
                    Text(conversation.name)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                        .foregroundColor(.primary)
                }
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selectedConversationId == conversation.id ? .blue.opacity(0.2) : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.blue.opacity(0.4), lineWidth: selectedConversationId == conversation.id ? 1 : 0)
        )
        .onTapGesture {
            selectedConversationId = conversation.id
        }
        .contextMenu {
            Button("Rename") {
                viewModel.editingConversationNameId = conversation.id
                newName = conversation.name
            }
            if viewModel.conversations.count > 1 {
                Button("Delete", role: .destructive) {
                    viewModel.deleteConversation(id: conversation.id)
                }
            }
        }
    }
}

// --- ChatPanelView ---
struct ChatPanelView: View {
    let conversationId: UUID
    @ObservedObject var viewModel: ChatViewModel
    @State private var messageText = ""
    @State private var isLoading = false
    @State private var showingSettings = false
    @State private var editingMessageId: UUID? = nil
    @State private var editingText: String = ""
    @State private var hoveredMessageId: UUID? = nil
    @State private var showNodeTree = false
    @State private var typingMessageId: UUID? = nil
    @State private var typingVisibleText: String = ""
    @State private var typingFullText: String = ""
    @State private var typingTimer: Timer? = nil
    @State private var canSendMessage = true
    var body: some View {
        ScrollViewReader { proxy in
            ZStack {
                VStack(spacing: 0) {
                    HStack {
                        Text(viewModel.getConversationName(for: conversationId))
                            .font(.title2)
                            .fontWeight(.semibold)
                        Spacer()
                        Button(action: { showingSettings = true }) {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                        Button(action: {}) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 16))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding()
                    .background(.ultraThinMaterial.opacity(0.3))
                    Divider().opacity(0.2)
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            let messages = viewModel.getMessages(for: conversationId)
                            if messages.isEmpty {
                                VStack(spacing: 20) {
                                    Image(systemName: "message.circle")
                                        .font(.system(size: 60))
                                        .foregroundColor(.secondary.opacity(0.5))
                                    Text("Start a conversation")
                                        .font(.title3)
                                        .fontWeight(.medium)
                                        .foregroundColor(.secondary)
                                    Text("Send a message to begin chatting with AI")
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.top, 100)
                            } else {
                                ForEach(messages) { tree in
                                    HStack(alignment: .top, spacing: 4) {
                                        Spacer(minLength: 120)
                                        VStack(alignment: .trailing, spacing: 4) {
                                            if editingMessageId == tree.id {
                                                TextField("Edit message", text: $editingText, onCommit: {
                                                    let trimmed = editingText.trimmingCharacters(in: .whitespacesAndNewlines)
                                                    if !trimmed.isEmpty {
                                                        viewModel.editMessage(conversationId: conversationId, messageId: tree.id, newText: trimmed)
                                                        getAIResponse(for: trimmed, editingMessageId: tree.id)
                                                    }
                                                    editingMessageId = nil
                                                })
                                                .textFieldStyle(.plain)
                                                .padding(8)
                                                .background(.ultraThinMaterial)
                                                .cornerRadius(12)
                                                .frame(maxWidth: 300)
                                                .onAppear { editingText = tree.text }
                                            } else {
                                                VStack(alignment: .trailing, spacing: 4) {
                                                    if !tree.branches.isEmpty {
                                                        HStack(spacing: 4) {
                                                            Button(action: {
                                                                let newIdx = max(0, tree.selectedBranchId.map { tree.branches.firstIndex(where: { $0.id == $0 }) ?? 0 } - 1)
                                                                viewModel.selectBranch(conversationId: conversationId, messageId: tree.id, branchId: tree.branches[newIdx].id)
                                                            }) {
                                                                Image(systemName: "chevron.left")
                                                                    .font(.system(size: 10))
                                                                    .foregroundColor(.secondary)
                                                            }
                                                            .buttonStyle(.plain)
                                                            .disabled(tree.selectedBranchId.map { tree.branches.firstIndex(where: { $0.id == $0 }) == 0 } ?? true)
                                                            Text("Edit \(tree.selectedBranchId.map { tree.branches.firstIndex(where: { $0.id == $0 })! + 1 } ?? 1) of \(tree.branches.count)")
                                                                .font(.caption2)
                                                                .foregroundColor(.secondary)
                                                            Button(action: {
                                                                let newIdx = min(tree.branches.count - 1, tree.selectedBranchId.map { tree.branches.firstIndex(where: { $0.id == $0 })! + 1 } ?? 0)
                                                                viewModel.selectBranch(conversationId: conversationId, messageId: tree.id, branchId: tree.branches[newIdx].id)
                                                            }) {
                                                                Image(systemName: "chevron.right")
                                                                    .font(.system(size: 10))
                                                                    .foregroundColor(.secondary)
                                                            }
                                                            .buttonStyle(.plain)
                                                            .disabled(tree.selectedBranchId.map { tree.branches.firstIndex(where: { $0.id == $0 }) == tree.branches.count - 1 } ?? true)
                                                        }
                                                        .padding(.horizontal, 12)
                                                        .padding(.vertical, 4)
                                                        .background(.ultraThinMaterial.opacity(0.5))
                                                        .cornerRadius(12)
                                                    }
                                                    Text(tree.text)
                                                        .padding(.horizontal, 16)
                                                        .padding(.vertical, 10)
                                                        .background(.blue)
                                                        .foregroundColor(.white)
                                                        .cornerRadius(18)
                                                        .textSelection(.enabled)
                                                    HStack(spacing: 8) {
                                                        if hoveredMessageId == tree.id {
                                                            HStack(spacing: 6) {
                                                                Button(action: {
                                                                    NSPasteboard.general.setString(tree.text, forType: .string)
                                                                }) {
                                                                    Image(systemName: "doc.on.doc")
                                                                        .font(.system(size: 12))
                                                                        .foregroundColor(.secondary)
                                                                        .padding(4)
                                                                }
                                                                .buttonStyle(.plain)
                                                                .background(.ultraThinMaterial)
                                                                .clipShape(Circle())
                                                                Button(action: {
                                                                    editingMessageId = tree.id
                                                                    editingText = tree.text
                                                                }) {
                                                                    Image(systemName: "pencil")
                                                                        .font(.system(size: 12))
                                                                        .foregroundColor(.secondary)
                                                                        .padding(4)
                                                                }
                                                                .buttonStyle(.plain)
                                                                .background(.ultraThinMaterial)
                                                                .clipShape(Circle())
                                                            }
                                                            .transition(.opacity)
                                                        }
                                                        Text(formatTime(tree.timestamp))
                                                            .font(.caption2)
                                                            .foregroundColor(.secondary)
                                                    }
                                                    .padding(.horizontal, 4)
                                                }
                                                .onHover { hovering in
                                                    withAnimation(.easeInOut(duration: 0.2)) {
                                                        hoveredMessageId = hovering ? tree.id : nil
                                                    }
                                                }
                                            }
                                        }
                                        .padding(.trailing, 16)
                                    }
                                    .id(tree.id)
                                    if !tree.branches.isEmpty && tree.selectedBranchId.map { tree.branches.firstIndex(where: { $0.id == $0 })! } < tree.branches.count {
                                        let currentBranch = tree.branches[tree.selectedBranchId.map { tree.branches.firstIndex(where: { $0.id == $0 })! }]
                                        let isTyping = typingMessageId == currentBranch.aiMessage.id
                                        HStack(alignment: .top, spacing: 4) {
                                            HStack {
                                                Text(isTyping ? typingVisibleText : currentBranch.aiMessage.text)
                                                    .padding(.horizontal, 16)
                                                    .padding(.vertical, 10)
                                                    .background(.ultraThinMaterial)
                                                    .foregroundColor(.primary)
                                                    .cornerRadius(18)
                                                    .textSelection(.enabled)
                                            }
                                            if tree.branches.count > 1 {
                                                HStack(spacing: 8) {
                                                    Text("Response \(tree.selectedBranchId.map { tree.branches.firstIndex(where: { $0.id == $0 })! + 1 } ?? 1) of \(tree.branches.count)")
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)
                                                    HStack(spacing: 4) {
                                                        Button(action: {
                                                            let newIndex = tree.selectedBranchId.map { tree.branches.firstIndex(where: { $0.id == $0 })! > 0 ? tree.branches.firstIndex(where: { $0.id == $0 })! - 1 : tree.branches.count - 1 } ?? 0
                                                            viewModel.selectBranch(conversationId: conversationId, messageId: tree.id, branchId: tree.branches[newIndex].id)
                                                        }) {
                                                            Image(systemName: "chevron.left")
                                                                .font(.system(size: 10))
                                                        }
                                                        .buttonStyle(.plain)
                                                        .background(.ultraThinMaterial)
                                                        .clipShape(Circle())
                                                        ForEach(tree.branches.indices, id: \.self) { idx in
                                                            Button(action: {
                                                                viewModel.selectBranch(conversationId: conversationId, messageId: tree.id, branchId: tree.branches[idx].id)
                                                            }) {
                                                                Circle()
                                                                    .fill(idx == tree.selectedBranchId.map { tree.branches.firstIndex(where: { $0.id == $0 })! } ? .blue : .secondary.opacity(0.3))
                                                                    .frame(width: 8, height: 8)
                                                            }
                                                            .buttonStyle(.plain)
                                                        }
                                                        Button(action: {
                                                            let newIndex = tree.selectedBranchId.map { tree.branches.firstIndex(where: { $0.id == $0 })! < tree.branches.count - 1 ? tree.branches.firstIndex(where: { $0.id == $0 })! + 1 : 0 } ?? 0
                                                            viewModel.selectBranch(conversationId: conversationId, messageId: tree.id, branchId: tree.branches[newIndex].id)
                                                        }) {
                                                            Image(systemName: "chevron.right")
                                                                .font(.system(size: 10))
                                                        }
                                                        .buttonStyle(.plain)
                                                        .background(.ultraThinMaterial)
                                                        .clipShape(Circle())
                                                    }
                                                }
                                                .padding(.horizontal, 16)
                                                .padding(.vertical, 4)
                                                .background(.ultraThinMaterial.opacity(0.5))
                                                .cornerRadius(12)
                                            }
                                            Text(formatTime(currentBranch.aiMessage.timestamp))
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                                .padding(.horizontal, 4)
                                        }
                                        .padding(.leading, 16)
                                        Spacer(minLength: 120)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 20)
                        .onChange(of: viewModel.getMessages(for: conversationId).flatMap { $0.allMessages }.count) {
                            let allMessages = viewModel.getMessages(for: conversationId).flatMap { $0.allMessages }
                            if let lastMessage = allMessages.last {
                                withAnimation(.easeOut(duration: 0.3)) {
                                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                    Divider().opacity(0.2)
                    HStack(spacing: 12) {
                        TextField("Message", text: $messageText, axis: .vertical)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(.ultraThinMaterial)
                            .cornerRadius(24)
                            .lineLimit(1...6)
                            .font(.system(size: 16))
                            .onSubmit {
                                sendMessage()
                            }
                        Button(action: { showNodeTree.toggle() }) {
                            Image(systemName: "rectangle.3.offgrid.bubble.left")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(12)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        Button(action: sendMessage) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary : .blue)
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSendMessage || messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(.ultraThinMaterial)
                }
                if showNodeTree {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture { showNodeTree = false }
                    NodeTreeOverlay(
                        messages: viewModel.getMessages(for: conversationId),
                        viewModel: viewModel,
                        conversationId: conversationId,
                        onBranchSelect: { messageId, branchIdx in
                            viewModel.selectBranch(conversationId: conversationId, messageId: messageId, branchId: viewModel.getMessages(for: conversationId)[branchIdx].branches[branchIdx].id)
                        },
                        onNodeSelect: { nodeId in
                            withAnimation {
                                proxy.scrollTo(nodeId, anchor: .center)
                            }
                            showNodeTree = false
                        },
                        onClose: { showNodeTree = false }
                    )
                }
            }
            .frame(minWidth: 600, minHeight: 400)
            .background(.ultraThinMaterial)
            .sheet(isPresented: $showingSettings) {
                AISettingsView(viewModel: viewModel)
            }
            .onChange(of: viewModel.getMessages(for: conversationId).last?.branches.last?.aiMessage.id) { newId in
                guard let newId = newId,
                      let aiMessage = viewModel.getMessages(for: conversationId).last?.branches.last?.aiMessage else { return }
                typingMessageId = newId
                typingFullText = aiMessage.text
                typingVisibleText = aiMessage.text
                typingTimer?.invalidate()
                typingTimer = nil
                canSendMessage = true
            }
        }
    }
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    private func sendMessage() {
        guard canSendMessage else { return }
        let trimmedMessage = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else { return }
        canSendMessage = false
        let userMessage = Message(id: UUID(), text: trimmedMessage, isCurrentUser: true, timestamp: Date())
        viewModel.addMessage(userMessage, to: conversationId)
        messageText = ""
        if let lastTree = viewModel.getMessages(for: conversationId).last {
            getAIResponse(for: trimmedMessage, editingMessageId: lastTree.id)
        }
    }
    private func getAIResponse(for userMessage: String, editingMessageId: UUID? = nil) {
        isLoading = true
        print("🔄 Starting AI request for message: '\(userMessage)'")
        guard let url = URL(string: "http://127.0.0.1:1234/v1/chat/completions") else {
            print("❌ Invalid API URL")
            addErrorMessage("Invalid API URL")
            return
        }
        print("🌐 URL created successfully: \(url)")
        let conversationHistory = viewModel.getMessages(for: conversationId)
        var messages: [[String: String]] = []
        messages.append([
            "role": "system",
            "content": viewModel.aiSettings.systemPrompt
        ])
        let recentMessages = conversationHistory.suffix(10)
        for tree in recentMessages {
            if tree.text.starts(with: "Error:") { continue }
            messages.append([
                "role": tree.isCurrentUser ? "user" : "assistant",
                "content": tree.text
            ])
            if !tree.branches.isEmpty && tree.selectedBranchId.map { tree.branches.firstIndex(where: { $0.id == $0 })! } < tree.branches.count {
                let aiBranch = tree.branches[tree.selectedBranchId.map { tree.branches.firstIndex(where: { $0.id == $0 })! }]
                messages.append([
                    "role": "assistant",
                    "content": aiBranch.aiMessage.text
                ])
            }
        }
        if messages.last?["content"] != userMessage {
            messages.append([
                "role": "user",
                "content": userMessage
            ])
        }
        var requestBody: [String: Any] = [
            "model": viewModel.aiSettings.model,
            "messages": messages,
            "temperature": viewModel.aiSettings.temperature,
            "max_tokens": viewModel.aiSettings.maxTokens,
            "stream": false,
            "top_p": viewModel.aiSettings.topP,
            "frequency_penalty": viewModel.aiSettings.frequencyPenalty,
            "presence_penalty": viewModel.aiSettings.presencePenalty
        ]
        if viewModel.aiSettings.topK > 0 {
            requestBody["top_k"] = viewModel.aiSettings.topK
        }
        print("📝 Request body created with \(messages.count) messages")
        print("🎛️ Settings: temp=\(viewModel.aiSettings.temperature), max_tokens=\(viewModel.aiSettings.maxTokens), top_p=\(viewModel.aiSettings.topP), top_k=\(viewModel.aiSettings.topK)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            print("✅ Request body serialized successfully")
        } catch {
            print("❌ Failed to encode request: \(error)")
            addErrorMessage("Failed to encode request")
            return
        }
        print("🚀 Starting URLSession request...")
        URLSession.shared.dataTask(with: request) { data, response, error in
            isLoading = false
            guard let data = data, error == nil else {
                print("❌ Network error: \(error?.localizedDescription ?? "Unknown error")")
                addErrorMessage("Network error: \(error?.localizedDescription ?? "Unknown error")")
                return
            }
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let firstChoice = choices.first,
                   let message = firstChoice["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    print("✅ Successfully parsed OpenAI format response")
                    let aiMessage = Message(id: UUID(), text: content.trimmingCharacters(in: .whitespacesAndNewlines), isCurrentUser: false, timestamp: Date())
                    if let editId = editingMessageId {
                        viewModel.addAIResponse(to: conversationId, messageId: editId, aiMessage: aiMessage)
                    }
                    return
                }
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let response = json["response"] as? String {
                    print("✅ Successfully parsed direct response format")
                    let aiMessage = Message(id: UUID(), text: response.trimmingCharacters(in: .whitespacesAndNewlines), isCurrentUser: false, timestamp: Date())
                    if let editId = editingMessageId {
                        viewModel.addAIResponse(to: conversationId, messageId: editId, aiMessage: aiMessage)
                    }
                    return
                }
                let completion = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["completion"] as? String
                if let completion = completion {
                    print("✅ Successfully parsed completion format")
                    let aiMessage = Message(id: UUID(), text: completion.trimmingCharacters(in: .whitespacesAndNewlines), isCurrentUser: false, timestamp: Date())
                    if let editId = editingMessageId {
                        viewModel.addAIResponse(to: conversationId, messageId: editId, aiMessage: aiMessage)
                    }
                    return
                }
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let text = json["text"] as? String {
                    print("✅ Successfully parsed text format")
                    let aiMessage = Message(id: UUID(), text: text.trimmingCharacters(in: .whitespacesAndNewlines), isCurrentUser: false, timestamp: Date())
                    if let editId = editingMessageId {
                        viewModel.addAIResponse(to: conversationId, messageId: editId, aiMessage: aiMessage)
                    }
                    return
                }
                print("❌ Could not parse any known response format")
                addErrorMessage("Unexpected response format. Check console for raw response.")
            } catch {
                print("❌ JSON parsing error: \(error.localizedDescription)")
                addErrorMessage("Failed to parse response: \(error.localizedDescription)")
            }
        }.resume()
    }
    private func addErrorMessage(_ error: String) {
        let errorMessage = Message(id: UUID(), text: "Error: \(error)", isCurrentUser: false, timestamp: Date())
        if let lastTree = viewModel.getMessages(for: conversationId).last {
            viewModel.addAIResponse(to: conversationId, messageId: lastTree.id, aiMessage: errorMessage)
        }
    }
}

// --- NodeTreeOverlay ---
struct NodeTreeOverlay: View {
    let messages: [MessageTree]
    let viewModel: ChatViewModel
    let conversationId: UUID
    let onBranchSelect: (UUID, Int) -> Void
    let onNodeSelect: (UUID) -> Void
    let onClose: () -> Void
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Conversation Tree")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        Text("Navigate your message branches")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary)
                            .background(Color.secondary.opacity(0.1), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 24)
                Divider().opacity(0.15)
                ScrollView([.horizontal, .vertical]) {
                    FlowchartTreeView(
                        messages: messages,
                        viewModel: viewModel,
                        conversationId: conversationId,
                        onBranchSelect: onBranchSelect,
                        onMessageBranchSelect: { messageId, branchIdx in
                            viewModel.selectBranch(conversationId: conversationId, messageId: messageId, branchId: messages[branchIdx].branches[branchIdx].id)
                            onNodeSelect(messageId)
                        },
                        onNodeSelect: onNodeSelect
                    )
                    .padding(60)
                }
                .background(Color.gray.opacity(0.08))
            }
            .frame(
                width: max(min(geometry.size.width * 0.85, 900), 350),
                height: max(min(geometry.size.height * 0.85, 700), 350)
            )
            .background(RoundedRectangle(cornerRadius: 28).fill(Color(NSColor.windowBackgroundColor)).shadow(color: .black.opacity(0.07), radius: 24, x: 0, y: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 28)
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
            )
            .position(
                x: geometry.size.width / 2,
                y: geometry.size.height / 2
            )
        }
    }
}

// --- FlowchartTreeView ---
struct FlowchartTreeView: View {
    let messages: [MessageTree]
    let viewModel: ChatViewModel
    let conversationId: UUID
    let onBranchSelect: (UUID, Int) -> Void
    let onMessageBranchSelect: (UUID, Int) -> Void
    let onNodeSelect: (UUID) -> Void
    var body: some View {
        VStack(spacing: 60) {
            ForEach(Array(messages.enumerated()), id: \.element.id) { messageIndex, tree in
                FlowchartNode(
                    tree: tree,
                    messageIndex: messageIndex,
                    isLast: messageIndex == messages.count - 1,
                    viewModel: viewModel,
                    conversationId: conversationId,
                    onBranchSelect: onBranchSelect,
                    onMessageBranchSelect: onMessageBranchSelect,
                    onNodeSelect: onNodeSelect
                )
            }
        }
    }
}

// --- FlowchartNode ---
struct FlowchartNode: View {
    let tree: MessageTree
    let messageIndex: Int
    let isLast: Bool
    let viewModel: ChatViewModel
    let conversationId: UUID
    let onBranchSelect: (UUID, Int) -> Void
    let onMessageBranchSelect: (UUID, Int) -> Void
    let onNodeSelect: (UUID) -> Void
    private var currentMessage: String {
        if tree.branches.isEmpty {
            return tree.text
        } else {
            return tree.branches[tree.selectedBranchId.map { tree.branches.firstIndex(where: { $0.id == $0 })! }]
        }
    }
    var body: some View {
        VStack(spacing: 40) {
            VStack(spacing: 20) {
                if tree.branches.count > 1 {
                    HStack(spacing: 30) {
                        ForEach(Array(tree.branches.enumerated()), id: \.element.id) { branchIdx, branch in
                            FlowchartMessageBox(
                                text: branch.aiMessage.text,
                                title: branchIdx == 0 ? "Original" : "Edit \(branchIdx)",
                                isSelected: tree.selectedBranchId.map { tree.branches.firstIndex(where: { $0.id == $0 })! } == branchIdx,
                                isUser: true,
                                onTap: {
                                    onMessageBranchSelect(tree.id, branchIdx)
                                }
                            )
                        }
                    }
                } else {
                    FlowchartMessageBox(
                        text: currentMessage,
                        title: "Question \(messageIndex + 1)",
                        isSelected: true,
                        isUser: true,
                        onTap: {}
                    )
                }
                if !isLast {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.4))
                        .frame(width: 3, height: 40)
                }
            }
        }
    }
}

// --- FlowchartMessageBox ---
struct FlowchartMessageBox: View {
    let text: String
    let title: String
    let isSelected: Bool
    let isUser: Bool
    let onTap: () -> Void
    private var displayText: String {
        text.count > 120 ? String(text.prefix(120)) + "..." : text
    }
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(displayText)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(width: 200, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isUser ? Color.blue.opacity(0.1) : Color.green.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            isSelected ?
                                (isUser ? Color.blue : Color.green) :
                                Color.secondary.opacity(0.3),
                            lineWidth: isSelected ? 2 : 1
                        )
                )
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(6)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

// --- AISettingsView ---
struct AISettingsView: View {
    @ObservedObject var viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationView {
            Form {
                Section("System Prompt") {
                    TextEditor(text: $viewModel.aiSettings.systemPrompt)
                        .frame(minHeight: 100)
                        .onChange(of: viewModel.aiSettings.systemPrompt) {
                            viewModel.saveSettings()
                        }
                }
                Section("Model Settings") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Temperature:")
                            Spacer()
                            Text("\(viewModel.aiSettings.temperature, specifier: "%.2f")")
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $viewModel.aiSettings.temperature, in: 0.0...2.0, step: 0.1)
                            .onChange(of: viewModel.aiSettings.temperature) {
                                viewModel.saveSettings()
                            }
                        Text("Controls randomness. Higher = more creative, lower = more focused")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Max Tokens:")
                            Spacer()
                            Text("\(viewModel.aiSettings.maxTokens)")
                                .foregroundColor(.secondary)
                        }
                        Slider(value: Binding(
                            get: { Double(viewModel.aiSettings.maxTokens) },
                            set: { viewModel.aiSettings.maxTokens = Int($0) }
                        ), in: 100...4000, step: 100)
                            .onChange(of: viewModel.aiSettings.maxTokens) {
                                viewModel.saveSettings()
                            }
                        Text("Maximum length of AI responses")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Top P:")
                            Spacer()
                            Text("\(viewModel.aiSettings.topP, specifier: "%.2f")")
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $viewModel.aiSettings.topP, in: 0.1...1.0, step: 0.05)
                            .onChange(of: viewModel.aiSettings.topP) {
                                viewModel.saveSettings()
                            }
                        Text("Alternative to temperature. Controls diversity of word choices")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Top K:")
                            Spacer()
                            Text("\(viewModel.aiSettings.topK)")
                                .foregroundColor(.secondary)
                        }
                        Slider(value: Binding(
                            get: { Double(viewModel.aiSettings.topK) },
                            set: { viewModel.aiSettings.topK = Int($0) }
                        ), in: 1...100, step: 1)
                            .onChange(of: viewModel.aiSettings.topK) {
                                viewModel.saveSettings()
                            }
                        Text("Limits vocabulary choices to top K most likely words")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Section("Model") {
                    TextField("Model Name", text: $viewModel.aiSettings.model)
                        .onChange(of: viewModel.aiSettings.model) {
                            viewModel.saveSettings()
                        }
                }
                Section {
                    Button("Reset to Defaults") {
                        viewModel.resetSettingsToDefault()
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationTitle("AI Settings")
            .toolbar {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .frame(minWidth: 500, minHeight: 600)
    }
}

// TypingIndicatorView for animated dots
struct TypingIndicatorView: View {
    @State private var phase: Int = 0
    @State private var timer: Timer?
    let dotCount = 3
    let dotSize: CGFloat = 8
    let dotSpacing: CGFloat = 6
    let animation = Animation.easeInOut(duration: 0.5).repeatForever(autoreverses: true)
    
    var body: some View {
        HStack(spacing: dotSpacing) {
            ForEach(0..<dotCount, id: \.self) { i in
                Circle()
                    .fill(Color.gray)
                    .frame(width: dotSize, height: dotSize)
                    .opacity(phase == i ? 1 : 0.4)
            }
        }
        .onAppear {
            withAnimation(animation) {
                timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
                    phase = (phase + 1) % dotCount
                }
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }
}

// MessageBubbleView for rendering messages
struct MessageBubbleView: View {
    let message: Message
    let isUser: Bool
    
    var body: some View {
        HStack {
            if isUser { Spacer() }
            Text(message.text)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(isUser ? Color.blue : Color(NSColor.windowBackgroundColor).opacity(0.8))
                .foregroundColor(isUser ? .white : .primary)
                .cornerRadius(18)
                .textSelection(.enabled)
                .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
            if !isUser { Spacer() }
        }
        .padding(.horizontal, 8)
    }
}

struct MessageTreeView: View {
    let messageTree: MessageTree
    let viewModel: ChatViewModel
    let conversationId: UUID
    let onBranchSelect: (UUID, Int) -> Void
    let onNodeSelect: (UUID) -> Void
    @State private var showTypingIndicator = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(messageTree.allMessages) { message in
                MessageBubbleView(message: message, isUser: message.isCurrentUser)
            }
            
            if showTypingIndicator {
                HStack {
                    TypingIndicatorView()
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color(NSColor.windowBackgroundColor).opacity(0.8))
                        .cornerRadius(18)
                    Spacer()
                }
                .padding(.horizontal, 8)
            }
        }
        .onChange(of: messageTree.branches.count) { newCount in
            if newCount > 0 {
                showTypingIndicator = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    showTypingIndicator = false
                }
            }
        }
    }
} 
