//
//  ContentView.swift
//  CALAPP
//
//  Created by Michael Knaap on 05/06/2025.
//

import SwiftUI
import Foundation

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
    var id = UUID()
    var name: String
    var messages: [MessageTree]
    let createdAt: Date
    
    init(name: String) {
        self.name = name
        self.messages = []
        self.createdAt = Date()
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
        systemPrompt: "You are a helpful, intelligent, and creative AI assistant. Provide thoughtful, detailed, and engaging responses. Be concise when appropriate but don't hesitate to elaborate when helpful. Always be friendly and professional.",
        temperature: 0.8,
        maxTokens: 2000,
        topP: 0.9,
        topK: 40,
        frequencyPenalty: 0.1,
        presencePenalty: 0.1,
        model: "dolphin-2.9.4-llama3.1-8b"
    )
    
    init(systemPrompt: String, temperature: Double, maxTokens: Int, topP: Double, topK: Int, frequencyPenalty: Double, presencePenalty: Double, model: String) {
        self.systemPrompt = systemPrompt
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.topP = topP
        self.topK = topK
        self.frequencyPenalty = frequencyPenalty
        self.presencePenalty = presencePenalty
        self.model = model
    }
}

// MessageTree for branching edits
struct MessageTree: Identifiable, Codable {
    var id: UUID
    var text: String
    var isCurrentUser: Bool
    var timestamp: Date
    // aiResponses is now [[MessageBranch]]: one array per message branch
    var aiResponsesPerBranch: [[MessageBranch]]
    var selectedBranch: Int
    var messageBranches: [MessageVersion]  // For message edit branches
    var selectedMessageBranch: Int
    // For history, keep all AI responses ever generated (hidden)
    var allAIResponses: [MessageBranch]
    
    var allMessages: [Message] {
        let currentMessageVersion = messageBranches.isEmpty ? 
            MessageVersion(text: text, timestamp: timestamp) : 
            messageBranches[selectedMessageBranch]
        var arr: [Message] = [Message(id: id, text: currentMessageVersion.text, isCurrentUser: isCurrentUser, timestamp: currentMessageVersion.timestamp)]
        if !aiResponsesPerBranch.isEmpty && selectedMessageBranch < aiResponsesPerBranch.count {
            let aiBranches = aiResponsesPerBranch[selectedMessageBranch]
            if !aiBranches.isEmpty {
                arr.append(aiBranches[selectedBranch].aiMessage)
            }
        }
        return arr
    }
    
    init(id: UUID = UUID(), text: String, isCurrentUser: Bool, timestamp: Date = Date(), aiResponsesPerBranch: [[MessageBranch]] = [], selectedBranch: Int = 0, messageBranches: [MessageVersion] = [], selectedMessageBranch: Int = 0, allAIResponses: [MessageBranch] = []) {
        self.id = id
        self.text = text
        self.isCurrentUser = isCurrentUser
        self.timestamp = timestamp
        self.aiResponsesPerBranch = aiResponsesPerBranch
        self.selectedBranch = selectedBranch
        self.messageBranches = messageBranches
        self.selectedMessageBranch = selectedMessageBranch
        self.allAIResponses = allAIResponses
    }
    
    // Get the current message text (considering branches)
    var currentText: String {
        return messageBranches.isEmpty ? text : messageBranches[selectedMessageBranch].text
    }
    
    // Get the current message timestamp (considering branches)
    var currentTimestamp: Date {
        return messageBranches.isEmpty ? timestamp : messageBranches[selectedMessageBranch].timestamp
    }
}

struct MessageBranch: Identifiable, Codable {
    var id: UUID
    var aiMessage: Message
    var createdAt: Date
    
    init(id: UUID = UUID(), aiMessage: Message, createdAt: Date = Date()) {
        self.id = id
        self.aiMessage = aiMessage
        self.createdAt = createdAt
    }
}

// For message edit branches
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

class ChatViewModel: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var selectedConversationId: UUID?
    @Published var aiSettings = AISettings.default
    @Published var editingConversationNameId: UUID? = nil
    @Published var editingMessageId: UUID? = nil
    
    var selectedConversation: Conversation? {
        conversations.first { $0.id == selectedConversationId }
    }
    
    init() {
        // Start with one default conversation
        createNewConversation(name: "General Chat", autoRename: false)
        loadSettings()
    }
    
    func createNewConversation(name: String, autoRename: Bool = true) {
        let newConversation = Conversation(name: name)
        conversations.insert(newConversation, at: 0)
        selectedConversationId = newConversation.id
        if autoRename {
            editingConversationNameId = newConversation.id
        }
    }
    
    func deleteConversation(id: UUID) {
        conversations.removeAll { $0.id == id }
        if selectedConversationId == id {
            selectedConversationId = conversations.first?.id
        }
    }
    
    func renameConversation(id: UUID, newName: String) {
        if let index = conversations.firstIndex(where: { $0.id == id }) {
            conversations[index].name = newName
        }
        editingConversationNameId = nil
    }
    
    func addMessage(_ message: Message, to conversationId: UUID) {
        if let index = conversations.firstIndex(where: { $0.id == conversationId }) {
            let tree = MessageTree(text: message.text, isCurrentUser: message.isCurrentUser)
            conversations[index].messages.append(tree)
        }
    }
    
    func getMessages(for conversationId: UUID) -> [MessageTree] {
        return conversations.first { $0.id == conversationId }?.messages ?? []
    }
    
    func getConversationName(for conversationId: UUID) -> String {
        return conversations.first { $0.id == conversationId }?.name ?? "Unknown"
    }
    
    func editMessage(conversationId: UUID, messageId: UUID, newText: String) {
        guard let cIdx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        guard let mIdx = conversations[cIdx].messages.firstIndex(where: { $0.id == messageId }) else { return }
        // Create a new message branch for the edited version
        let newMessageVersion = MessageVersion(text: newText, timestamp: Date())
        // If this is the first edit, initialize with the original message
        if conversations[cIdx].messages[mIdx].messageBranches.isEmpty {
            let originalVersion = MessageVersion(
                text: conversations[cIdx].messages[mIdx].text,
                timestamp: conversations[cIdx].messages[mIdx].timestamp,
                editedAt: conversations[cIdx].messages[mIdx].timestamp
            )
            conversations[cIdx].messages[mIdx].messageBranches = [originalVersion]
            // Also initialize aiResponsesPerBranch for the original
            conversations[cIdx].messages[mIdx].aiResponsesPerBranch = [[]]
        }
        // Add the new edited version
        conversations[cIdx].messages[mIdx].messageBranches.append(newMessageVersion)
        // Add a new empty aiResponses array for this branch
        conversations[cIdx].messages[mIdx].aiResponsesPerBranch.append([])
        conversations[cIdx].messages[mIdx].selectedMessageBranch = conversations[cIdx].messages[mIdx].messageBranches.count - 1
        conversations[cIdx].messages[mIdx].selectedBranch = 0
        // Remove all subsequent messages when editing (they belong to the old timeline)
        removeSubsequentMessages(conversationId: conversationId, afterMessageIndex: mIdx)
        editingMessageId = nil
    }
    
    func removeSubsequentMessages(conversationId: UUID, afterMessageIndex: Int) {
        guard let cIdx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        let keepUpTo = afterMessageIndex + 1
        if conversations[cIdx].messages.count > keepUpTo {
            conversations[cIdx].messages.removeSubrange(keepUpTo...)
        }
    }
    
    func selectMessageBranch(conversationId: UUID, messageId: UUID, branchIdx: Int) {
        guard let cIdx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        guard let mIdx = conversations[cIdx].messages.firstIndex(where: { $0.id == messageId }) else { return }
        conversations[cIdx].messages[mIdx].selectedMessageBranch = branchIdx
        // Reset selectedBranch to 0 if the new branch has no AI responses
        if conversations[cIdx].messages[mIdx].aiResponsesPerBranch.count > branchIdx {
            if conversations[cIdx].messages[mIdx].aiResponsesPerBranch[branchIdx].isEmpty {
                conversations[cIdx].messages[mIdx].selectedBranch = 0
            } else if conversations[cIdx].messages[mIdx].selectedBranch >= conversations[cIdx].messages[mIdx].aiResponsesPerBranch[branchIdx].count {
                conversations[cIdx].messages[mIdx].selectedBranch = 0
            }
        }
    }
    
    func addAIResponse(to conversationId: UUID, messageId: UUID, aiMessage: Message) {
        guard let cIdx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        guard let mIdx = conversations[cIdx].messages.firstIndex(where: { $0.id == messageId }) else { return }
        let branch = MessageBranch(aiMessage: aiMessage)
        let branchIdx = conversations[cIdx].messages[mIdx].selectedMessageBranch
        // Ensure aiResponsesPerBranch is initialized for all branches
        while conversations[cIdx].messages[mIdx].aiResponsesPerBranch.count <= branchIdx {
            conversations[cIdx].messages[mIdx].aiResponsesPerBranch.append([])
        }
        conversations[cIdx].messages[mIdx].aiResponsesPerBranch[branchIdx].append(branch)
        conversations[cIdx].messages[mIdx].selectedBranch = conversations[cIdx].messages[mIdx].aiResponsesPerBranch[branchIdx].count - 1
        // Store all AI responses for history
        conversations[cIdx].messages[mIdx].allAIResponses.append(branch)
        // Auto-generate title after 2 messages (1 user + 1 AI = 2)
        let allMessages = conversations[cIdx].messages.flatMap { $0.allMessages }
        if allMessages.count >= 2 && conversations[cIdx].name.contains("New Chat") {
            generateContextualTitle(for: conversationId)
        }
    }
    
    func generateContextualTitle(for conversationId: UUID) {
        guard let cIdx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        let messages = conversations[cIdx].messages.flatMap { $0.allMessages }
        
        // Take the first user message for context
        if let firstUserMessage = messages.first(where: { $0.isCurrentUser }) {
            let context = firstUserMessage.text.prefix(100) // Use first 100 chars
            let newTitle = generateTitleFromContext(String(context))
            conversations[cIdx].name = newTitle
        }
    }
    
    private func generateTitleFromContext(_ context: String) -> String {
        // Simple title generation based on keywords
        let lowercased = context.lowercased()
        
        if lowercased.contains("code") || lowercased.contains("programming") || lowercased.contains("function") {
            return "💻 Code Discussion"
        } else if lowercased.contains("recipe") || lowercased.contains("cook") || lowercased.contains("food") {
            return "🍳 Recipe Help"
        } else if lowercased.contains("write") || lowercased.contains("essay") || lowercased.contains("article") {
            return "✍️ Writing Assistant"
        } else if lowercased.contains("math") || lowercased.contains("calculate") || lowercased.contains("equation") {
            return "🧮 Math Help"
        } else if lowercased.contains("plan") || lowercased.contains("schedule") || lowercased.contains("organize") {
            return "📅 Planning Session"
        } else if lowercased.contains("learn") || lowercased.contains("explain") || lowercased.contains("understand") {
            return "🎓 Learning Session"
        } else if lowercased.contains("creative") || lowercased.contains("idea") || lowercased.contains("brainstorm") {
            return "💡 Creative Ideas"
        } else {
            // Fallback: use first few words
            let words = context.components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .prefix(3)
            return words.joined(separator: " ").capitalized
        }
    }
    
    func selectBranch(conversationId: UUID, messageId: UUID, branchIdx: Int) {
        guard let cIdx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        guard let mIdx = conversations[cIdx].messages.firstIndex(where: { $0.id == messageId }) else { return }
        conversations[cIdx].messages[mIdx].selectedBranch = branchIdx
    }
    
    func saveSettings() {
        if let encoded = try? JSONEncoder().encode(aiSettings) {
            UserDefaults.standard.set(encoded, forKey: "AISettings")
        }
    }
    
    func loadSettings() {
        if let data = UserDefaults.standard.data(forKey: "AISettings"),
           let decoded = try? JSONDecoder().decode(AISettings.self, from: data) {
            aiSettings = decoded
        }
    }
    
    func resetSettingsToDefault() {
        aiSettings = AISettings.default
        saveSettings()
    }
}

struct ContentView: View {
    @StateObject private var viewModel = ChatViewModel()
    @State private var selectedConversationId: UUID?
    
    var body: some View {
        ZStack {
            // Background blur effect
            BlurView(style: .underWindowBackground)
                .ignoresSafeArea()
            
            NavigationSplitView {
                // Sidebar
                SidebarView(viewModel: viewModel, selectedConversationId: $selectedConversationId)
                    .background(.ultraThinMaterial)
            } detail: {
                if let conversationId = selectedConversationId {
                    ChatPanelView(conversationId: conversationId, viewModel: viewModel)
                        .background(.ultraThinMaterial)
                } else {
                    // Empty state
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
        }
        .onAppear {
            // Auto-select first conversation if available
            if selectedConversationId == nil {
                selectedConversationId = viewModel.conversations.first?.id
            }
        }
    }
}

struct SidebarView: View {
    @ObservedObject var viewModel: ChatViewModel
    @Binding var selectedConversationId: UUID?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Recent Chats")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button(action: {
                    viewModel.createNewConversation(name: "New Chat")
                    // Auto-switch to the new conversation
                    selectedConversationId = viewModel.conversations.first?.id
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(.ultraThinMaterial.opacity(0.3))
            
            Divider()
                .opacity(0.2)
            
            // Conversations List
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.conversations) { conversation in
                        ConversationRowView(conversation: conversation, viewModel: viewModel, selectedConversationId: $selectedConversationId)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .frame(minWidth: 280, maxWidth: 350)
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
            // Icon
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 20)
            
            // Content
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
    // Typing animation state
    @State private var typingMessageId: UUID? = nil
    @State private var typingVisibleText: String = ""
    @State private var typingFullText: String = ""
    @State private var typingTimer: Timer? = nil
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Chat header
                HStack {
                    Text(viewModel.getConversationName(for: conversationId))
                        .font(.title2)
                        .fontWeight(.semibold)
                    Spacer()
                    
                    // AI Settings Button
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
                
                Divider()
                    .opacity(0.2)
                
                // Chat messages area
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            let messages = viewModel.getMessages(for: conversationId)
                            if messages.isEmpty {
                                VStack(spacing: 16) {
                                    Image(systemName: "message")
                                        .font(.system(size: 40))
                                        .foregroundColor(.secondary)
                                    Text("Start a new conversation")
                                        .font(.title3)
                                        .fontWeight(.medium)
                                    Text("Ask me anything!")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.top, 100)
        .padding()
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                            } else {
                                ForEach(messages) { tree in
                                    // User message
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
                                                .onAppear { editingText = tree.currentText }
                                            } else {
                                                VStack(alignment: .trailing, spacing: 4) {
                                                    // Message branch navigation (if there are branches)
                                                    if !tree.messageBranches.isEmpty {
                                                        HStack(spacing: 4) {
                                                            Button(action: {
                                                                let newIdx = max(0, tree.selectedMessageBranch - 1)
                                                                viewModel.selectMessageBranch(conversationId: conversationId, messageId: tree.id, branchIdx: newIdx)
                                                            }) {
                                                                Image(systemName: "chevron.left")
                                                                    .font(.system(size: 10))
                                                                    .foregroundColor(.secondary)
                                                            }
                                                            .buttonStyle(.plain)
                                                            .disabled(tree.selectedMessageBranch == 0)
                                                            
                                                            Text("Edit \(tree.selectedMessageBranch + 1) of \(tree.messageBranches.count)")
                                                                .font(.caption2)
                                                                .foregroundColor(.secondary)
                                                            
                                                            Button(action: {
                                                                let newIdx = min(tree.messageBranches.count - 1, tree.selectedMessageBranch + 1)
                                                                viewModel.selectMessageBranch(conversationId: conversationId, messageId: tree.id, branchIdx: newIdx)
                                                            }) {
                                                                Image(systemName: "chevron.right")
                                                                    .font(.system(size: 10))
                                                                    .foregroundColor(.secondary)
                                                            }
                                                            .buttonStyle(.plain)
                                                            .disabled(tree.selectedMessageBranch == tree.messageBranches.count - 1)
                                                        }
                                                        .padding(.horizontal, 12)
                                                        .padding(.vertical, 4)
                                                        .background(.ultraThinMaterial.opacity(0.5))
                                                        .cornerRadius(12)
                                                    }
                                                    
                                                    // Message bubble
                                                    Text(tree.currentText)
                                                        .padding(.horizontal, 16)
                                                        .padding(.vertical, 10)
                                                        .background(.blue)
                                                        .foregroundColor(.white)
                                                        .cornerRadius(18)
                                                        .textSelection(.enabled)
                                                    
                                                    // Timestamp and hover buttons
                                                    HStack(spacing: 8) {
                                                        // Hover buttons on the right
                                                        if hoveredMessageId == tree.id {
                                                            HStack(spacing: 6) {
                                                                Button(action: {
                                                                    NSPasteboard.general.setString(tree.currentText, forType: .string)
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
                                                                    editingText = tree.currentText
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
                                                        
                                                        Text(formatTime(tree.currentTimestamp))
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
                                    
                                    // AI response with branch navigation
                                    if !tree.aiResponsesPerBranch.isEmpty && tree.selectedMessageBranch < tree.aiResponsesPerBranch.count {
                                        let currentResponse = tree.aiResponsesPerBranch[tree.selectedMessageBranch][tree.selectedBranch]
                                        let isTyping = typingMessageId == currentResponse.aiMessage.id
                                        HStack(alignment: .top, spacing: 4) {
                                            VStack(alignment: .leading, spacing: 2) {
                                                HStack {
                                                    // AI message bubble
                                                    VStack(alignment: .leading, spacing: 2) {
                                                        Text(isTyping ? typingVisibleText : currentResponse.aiMessage.text)
                                                            .padding(.horizontal, 16)
                                                            .padding(.vertical, 10)
                                                            .background(.ultraThinMaterial)
                                                            .foregroundColor(.primary)
                                                            .cornerRadius(18)
                                                            .textSelection(.enabled)
                                                        Text(formatTime(currentResponse.aiMessage.timestamp))
                                                            .font(.caption2)
                                                            .foregroundColor(.secondary)
                                                            .padding(.horizontal, 4)
                                                    }
                                                    
                                                    // Copy button for AI response
                                                    Button(action: {
                                                        NSPasteboard.general.setString(currentResponse.aiMessage.text, forType: .string)
                                                    }) {
                                                        Image(systemName: "doc.on.doc")
                                                            .font(.system(size: 12))
                                                            .foregroundColor(.secondary)
                                                    }
                                                    .buttonStyle(.plain)
                                                    .background(.ultraThinMaterial)
                                                    .clipShape(Circle())
                                                    .opacity(0.7)
                                                }
                                                
                                                // Branch navigation if multiple responses
                                                if tree.aiResponsesPerBranch[tree.selectedMessageBranch].count > 1 {
                                                    HStack(spacing: 8) {
                                                        Text("Response \(tree.selectedBranch + 1) of \(tree.aiResponsesPerBranch[tree.selectedMessageBranch].count)")
                                                            .font(.caption2)
                                                            .foregroundColor(.secondary)
                                                        
                                                        HStack(spacing: 4) {
                                                            // Previous button
                                                            Button(action: {
                                                                let newIndex = tree.selectedBranch > 0 ? tree.selectedBranch - 1 : tree.aiResponsesPerBranch[tree.selectedMessageBranch].count - 1
                                                                viewModel.selectBranch(conversationId: conversationId, messageId: tree.id, branchIdx: newIndex)
                                                            }) {
                                                                Image(systemName: "chevron.left")
                                                                    .font(.system(size: 10))
                                                            }
                                                            .buttonStyle(.plain)
                                                            .background(.ultraThinMaterial)
                                                            .clipShape(Circle())
                                                            
                                                            // Branch indicators
                                                            ForEach(tree.aiResponsesPerBranch[tree.selectedMessageBranch].indices, id: \.self) { idx in
                                                                Button(action: {
                                                                    viewModel.selectBranch(conversationId: conversationId, messageId: tree.id, branchIdx: idx)
                                                                }) {
                                                                    Circle()
                                                                        .fill(idx == tree.selectedBranch ? .blue : .secondary.opacity(0.3))
                                                                        .frame(width: 8, height: 8)
                                                                }
                                                                .buttonStyle(.plain)
                                                            }
                                                            
                                                            // Next button
                                                            Button(action: {
                                                                let newIndex = tree.selectedBranch < tree.aiResponsesPerBranch[tree.selectedMessageBranch].count - 1 ? tree.selectedBranch + 1 : 0
                                                                viewModel.selectBranch(conversationId: conversationId, messageId: tree.id, branchIdx: newIndex)
                                                            }) {
                                                                Image(systemName: "chevron.right")
                                                                    .font(.system(size: 10))
                                                            }
                                                            .buttonStyle(.plain)
                                                            .background(.ultraThinMaterial)
                                                            .clipShape(Circle())
                                                        }
                                                    }
                                                    .padding(.leading, 16)
                                                    .padding(.top, 4)
                                                }
                                            }
                                            .padding(.leading, 16)
                                            Spacer(minLength: 60)
                                        }
                                        .id(currentResponse.aiMessage.id)
                                    }
                                }
                            }
                            
                            if isLoading {
                                HStack {
                                    HStack(spacing: 4) {
                                        ForEach(0..<3) { _ in
                                            Circle()
                                                .fill(Color.secondary)
                                                .frame(width: 8, height: 8)
                                                .scaleEffect(isLoading ? 1.0 : 0.5)
                                                .animation(
                                                    Animation.easeInOut(duration: 0.6)
                                                        .repeatForever()
                                                        .delay(Double.random(in: 0...0.6)),
                                                    value: isLoading
                                                )
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(.ultraThinMaterial)
                                    .cornerRadius(18)
                                    Spacer()
                                }
                                .padding(.horizontal)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onChange(of: viewModel.getMessages(for: conversationId).flatMap { $0.allMessages }.count) {
                        let allMessages = viewModel.getMessages(for: conversationId).flatMap { $0.allMessages }
                        if let lastMessage = allMessages.last {
                            withAnimation(.easeOut(duration: 0.3)) {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }
                
                Divider()
                    .opacity(0.2)
                
                // Message input
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
                    
                    // Node tree button
                    Button(action: { showNodeTree.toggle() }) {
                        Image(systemName: "tree")
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
                    .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(.ultraThinMaterial)
            }
        
        // Node tree overlay
        if showNodeTree {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { showNodeTree = false }
            
            NodeTreeOverlay(
                messages: viewModel.getMessages(for: conversationId),
                viewModel: viewModel,
                conversationId: conversationId,
                onBranchSelect: { messageId, branchIdx in
                    viewModel.selectBranch(conversationId: conversationId, messageId: messageId, branchIdx: branchIdx)
                },
                onClose: { showNodeTree = false }
            )
        }
        } // End of ZStack
        .frame(minWidth: 600, minHeight: 400)
        .background(.ultraThinMaterial)
        .sheet(isPresented: $showingSettings) {
            AISettingsView(viewModel: viewModel)
        }
        // Typing animation trigger
        .onChange(of: viewModel.getMessages(for: conversationId).last?.aiResponsesPerBranch.last?.last?.aiMessage.id) { newId in
            guard let newId = newId,
                  let aiMessage = viewModel.getMessages(for: conversationId).last?.aiResponsesPerBranch.last?.last?.aiMessage else { return }
            // Instantly show the full message, no animation
            typingMessageId = newId
            typingFullText = aiMessage.text
            typingVisibleText = aiMessage.text
            typingTimer?.invalidate()
            typingTimer = nil
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func sendMessage() {
        let trimmedMessage = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else { return }
        let userMessage = Message(id: UUID(), text: trimmedMessage, isCurrentUser: true, timestamp: Date())
        viewModel.addMessage(userMessage, to: conversationId)
        messageText = ""
        // Get AI response for the new message
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
        // Build conversation history for context
        let conversationHistory = viewModel.getMessages(for: conversationId)
        var messages: [[String: String]] = []
        // Add system prompt from settings
        messages.append([
            "role": "system",
            "content": viewModel.aiSettings.systemPrompt
        ])
        // Add recent conversation history (last 10 messages for context)
        let recentMessages = conversationHistory.suffix(10)
        for tree in recentMessages {
            if tree.text.starts(with: "Error:") { continue }
            messages.append([
                "role": tree.isCurrentUser ? "user" : "assistant",
                "content": tree.text
            ])
            if !tree.aiResponsesPerBranch.isEmpty && tree.selectedMessageBranch < tree.aiResponsesPerBranch.count {
                let aiBranches = tree.aiResponsesPerBranch[tree.selectedMessageBranch]
                if !aiBranches.isEmpty {
                    messages.append([
                        "role": "assistant",
                        "content": aiBranches[tree.selectedBranch].aiMessage.text
                    ])
                }
            }
        }
        // Add current message if not already included
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
            DispatchQueue.main.async {
                self.isLoading = false
                print("📥 URLSession response received")
                if let error = error {
                    print("❌ Network error: \(error.localizedDescription)")
                    addErrorMessage("Network error: \(error.localizedDescription)")
                    return
                }
                if let httpResponse = response as? HTTPURLResponse {
                    print("🔢 HTTP Status Code: \(httpResponse.statusCode)")
                }
                guard let data = data else {
                    print("❌ No response data")
                    addErrorMessage("No response data")
                    return
                }
                print("📊 Response data size: \(data.count) bytes")
                if let responseString = String(data: data, encoding: .utf8) {
                    print("📄 Raw response: \(responseString)")
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
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let completion = json["completion"] as? String {
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
                
                Section("Penalties") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Frequency Penalty:")
                            Spacer()
                            Text("\(viewModel.aiSettings.frequencyPenalty, specifier: "%.2f")")
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $viewModel.aiSettings.frequencyPenalty, in: -2.0...2.0, step: 0.1)
                            .onChange(of: viewModel.aiSettings.frequencyPenalty) {
                                viewModel.saveSettings()
                            }
                        Text("Reduces repetition of words that appear frequently")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Presence Penalty:")
                            Spacer()
                            Text("\(viewModel.aiSettings.presencePenalty, specifier: "%.2f")")
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $viewModel.aiSettings.presencePenalty, in: -2.0...2.0, step: 0.1)
                            .onChange(of: viewModel.aiSettings.presencePenalty) {
                                viewModel.saveSettings()
                            }
                        Text("Encourages talking about new topics")
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

struct MessageBubbleView: View {
    let message: Message
    
    var body: some View {
        HStack {
            if message.isCurrentUser {
                Spacer(minLength: 60)
            }
            
            VStack(alignment: message.isCurrentUser ? .trailing : .leading, spacing: 2) {
                Text(message.text)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(message.isCurrentUser ? Color.blue : Color(NSColor.controlBackgroundColor))
                    .foregroundColor(message.isCurrentUser ? .white : .primary)
                    .cornerRadius(18)
                    .textSelection(.enabled)
                
                Text(formatTime(message.timestamp))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
            }
            
            if !message.isCurrentUser {
                Spacer(minLength: 60)
            }
        }
        .padding(.horizontal)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// Add a BlurView for custom Gaussian blur if not available
import AppKit
struct BlurView: NSViewRepresentable {
    var style: NSVisualEffectView.Material = .contentBackground
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = style
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// Flowchart-style conversation tree overlay
struct NodeTreeOverlay: View {
    let messages: [MessageTree]
    let viewModel: ChatViewModel
    let conversationId: UUID
    let onBranchSelect: (UUID, Int) -> Void
    let onClose: () -> Void
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Conversation Tree")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        Text("Navigate through conversation branches")
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
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                
                Divider().opacity(0.3)
                
                // Flowchart content
                ScrollView([.horizontal, .vertical]) {
                    FlowchartTreeView(
                        messages: messages,
                        viewModel: viewModel,
                        conversationId: conversationId,
                        onBranchSelect: onBranchSelect,
                        onMessageBranchSelect: { messageId, branchIdx in
                            viewModel.selectMessageBranch(conversationId: conversationId, messageId: messageId, branchIdx: branchIdx)
                        }
                    )
                    .padding(40)
                }
                .background(Color.black.opacity(0.05))
            }
            .frame(
                width: min(max(geometry.size.width * 0.9, 900), 1200),
                height: min(max(geometry.size.height * 0.9, 700), 900)
            )
            .background(.ultraThinMaterial.opacity(0.98))
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(.tertiary.opacity(0.6), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.3), radius: 40, x: 0, y: 15)
            .position(
                x: geometry.size.width / 2,
                y: geometry.size.height / 2
            )
        }
    }
}

struct FlowchartTreeView: View {
    let messages: [MessageTree]
    let viewModel: ChatViewModel
    let conversationId: UUID
    let onBranchSelect: (UUID, Int) -> Void
    let onMessageBranchSelect: (UUID, Int) -> Void
    
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
                    onMessageBranchSelect: onMessageBranchSelect
                )
            }
        }
    }
}

struct FlowchartNode: View {
    let tree: MessageTree
    let messageIndex: Int
    let isLast: Bool
    let viewModel: ChatViewModel
    let conversationId: UUID
    let onBranchSelect: (UUID, Int) -> Void
    let onMessageBranchSelect: (UUID, Int) -> Void
    
    private var currentMessage: String {
        if tree.messageBranches.isEmpty {
            return tree.text
        } else {
            return tree.messageBranches[tree.selectedMessageBranch].text
        }
    }
    
    var body: some View {
        VStack(spacing: 40) {
            // User message node
            VStack(spacing: 20) {
                // Message branches if multiple versions exist
                if tree.messageBranches.count > 1 {
                    HStack(spacing: 30) {
                        ForEach(Array(tree.messageBranches.enumerated()), id: \.element.id) { branchIdx, messageVersion in
                            FlowchartMessageBox(
                                text: messageVersion.text,
                                title: branchIdx == 0 ? "Original" : "Edit \(branchIdx)",
                                isSelected: tree.selectedMessageBranch == branchIdx,
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
                
                // Connection line down
                if !tree.aiResponsesPerBranch.isEmpty && tree.selectedMessageBranch < tree.aiResponsesPerBranch.count {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.4))
                        .frame(width: 3, height: 40)
                }
            }
            
            // AI responses
            if !tree.aiResponsesPerBranch.isEmpty && tree.selectedMessageBranch < tree.aiResponsesPerBranch.count {
                VStack(spacing: 30) {
                    if tree.aiResponsesPerBranch[tree.selectedMessageBranch].count > 1 {
                        // Multiple AI responses - show as branches
                        HStack(spacing: 50) {
                            ForEach(Array(tree.aiResponsesPerBranch[tree.selectedMessageBranch].enumerated()), id: \.element.id) { branchIdx, branch in
                                VStack(spacing: 15) {
                                    FlowchartMessageBox(
                                        text: branch.aiMessage.text,
                                        title: "Route \(String(UnicodeScalar(65 + branchIdx)!))",
                                        isSelected: tree.selectedBranch == branchIdx,
                                        isUser: false,
                                        onTap: {
                                            onBranchSelect(tree.id, branchIdx)
                                        }
                                    )
                                }
                            }
                        }
                    } else {
                        // Single AI response
                        FlowchartMessageBox(
                            text: tree.aiResponsesPerBranch[tree.selectedMessageBranch][tree.selectedBranch].aiMessage.text,
                            title: "AI Response",
                            isSelected: true,
                            isUser: false,
                            onTap: {}
                        )
                    }
                }
            }
        }
    }
}

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
                // Message content box
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
                
                // Title label
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



#Preview {
    ContentView()
        .frame(width: 800, height: 600)
}
