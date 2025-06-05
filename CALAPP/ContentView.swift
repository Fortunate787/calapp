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

// Node System for Conversation Tree
struct ConversationNode: Identifiable, Codable {
    var id: UUID
    var label: String           // The question or message text
    var routeLabel: String?     // What choice led here (e.g. 'Route A')
    var parentId: UUID?         // The previous node
    var timestamp: Date         // When this question was shown
    var isCurrentUser: Bool
    var children: [UUID]        // Child node IDs
    var aiResponses: [AIResponse] // Multiple AI responses for this node
    var selectedResponseId: UUID? // Currently selected AI response
    
    init(id: UUID = UUID(), label: String, routeLabel: String? = nil, parentId: UUID? = nil, 
         timestamp: Date = Date(), isCurrentUser: Bool, children: [UUID] = [], 
         aiResponses: [AIResponse] = [], selectedResponseId: UUID? = nil) {
        self.id = id
        self.label = label
        self.routeLabel = routeLabel
        self.parentId = parentId
        self.timestamp = timestamp
        self.isCurrentUser = isCurrentUser
        self.children = children
        self.aiResponses = aiResponses
        self.selectedResponseId = selectedResponseId
    }
}

struct AIResponse: Identifiable, Codable {
    var id: UUID
    var text: String
    var timestamp: Date
    
    init(id: UUID = UUID(), text: String, timestamp: Date = Date()) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
    }
}

struct Conversation: Identifiable, Codable {
    var id: UUID
    var name: String
    var nodes: [UUID: ConversationNode] // Dictionary of all nodes
    var rootNodeId: UUID?               // Starting node
    var currentNodeId: UUID?            // Currently selected node
    let createdAt: Date
    
    init(id: UUID = UUID(), name: String, nodes: [UUID: ConversationNode] = [:], 
         rootNodeId: UUID? = nil, currentNodeId: UUID? = nil, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.nodes = nodes
        self.rootNodeId = rootNodeId
        self.currentNodeId = currentNodeId
        self.createdAt = createdAt
    }
    
    var lastMessagePreview: String {
        guard let currentNodeId = currentNodeId,
              let currentNode = nodes[currentNodeId] else { return "No messages" }
        return currentNode.label.prefix(50) + (currentNode.label.count > 50 ? "..." : "")
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }
    
    // Get path from root to current node
    func getPathToNode(_ nodeId: UUID) -> [ConversationNode] {
        var path: [ConversationNode] = []
        var currentId: UUID? = nodeId
        
        while let id = currentId, let node = nodes[id] {
            path.insert(node, at: 0)
            currentId = node.parentId
        }
        
        return path
    }
    
    // Get current conversation path
    func getCurrentPath() -> [ConversationNode] {
        guard let currentNodeId = currentNodeId else { return [] }
        return getPathToNode(currentNodeId)
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

// --- ViewModel ---
class ChatViewModel: ObservableObject {
    @Published var conversations: [UUID: Conversation] = [:]
    @Published var aiSettings: AISettings = .default
    @Published var selectedConversationId: UUID?
    @Published var editingConversationNameId: UUID?
    @Published var editingNodeId: UUID?
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
        conversations[newConversation.id] = newConversation
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
        conversations[id]?.name = newName
        editingConversationNameId = nil
    }
    
    func addMessage(_ message: String, to conversationId: UUID, isUser: Bool) {
        guard var conversation = conversations[conversationId] else { return }
        
        let newNode = ConversationNode(
            label: message,
            parentId: conversation.currentNodeId,
            isCurrentUser: isUser
        )
        
        // Add to parent's children if exists
        if let parentId = conversation.currentNodeId {
            conversation.nodes[parentId]?.children.append(newNode.id)
        } else {
            // This is the root node
            conversation.rootNodeId = newNode.id
        }
        
        conversation.nodes[newNode.id] = newNode
        conversation.currentNodeId = newNode.id
        conversations[conversationId] = conversation
        
        updateConversationName(conversationId)
    }
    
    func addAIResponse(to conversationId: UUID, nodeId: UUID, response: String) {
        guard var conversation = conversations[conversationId] else { return }
        
        let aiResponse = AIResponse(text: response)
        conversation.nodes[nodeId]?.aiResponses.append(aiResponse)
        conversation.nodes[nodeId]?.selectedResponseId = aiResponse.id
        
        conversations[conversationId] = conversation
    }
    
    func selectAIResponse(conversationId: UUID, nodeId: UUID, responseId: UUID) {
        conversations[conversationId]?.nodes[nodeId]?.selectedResponseId = responseId
    }
    
    func jumpToNode(conversationId: UUID, nodeId: UUID) {
        conversations[conversationId]?.currentNodeId = nodeId
    }
    
    func getConversationPath(for conversationId: UUID) -> [ConversationNode] {
        guard let conversation = conversations[conversationId] else { return [] }
        return conversation.getCurrentPath()
    }
    
    func editMessage(conversationId: UUID, nodeId: UUID, newText: String) {
        conversations[conversationId]?.nodes[nodeId]?.label = newText
        editingNodeId = nil
    }
    
    func generateContextualTitle(for conversationId: UUID) {
        guard let conversation = conversations[conversationId] else { return }
        
        let path = conversation.getCurrentPath()
        guard path.count >= 2 else { return }
        
        let context = path.prefix(2).map { $0.label }.joined(separator: " ")
        
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
                self?.conversations[conversationId]?.name = content.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }.resume()
    }
    
    func saveSettings() {
        // Implement settings persistence
    }
    
    func loadSettings() {
        // Implement settings loading
    }
    
    func resetSettingsToDefault() { 
        aiSettings = .default 
    }
    
    private func updateConversationName(_ conversationId: UUID) {
        guard let conversation = conversations[conversationId] else { return }
        
        let path = conversation.getCurrentPath()
        guard path.count >= 2 else { return }
        
        let context = path.prefix(2).map { $0.label }.joined(separator: " ")
        generateContextualTitle(for: conversationId)
    }
}

// --- Main ContentView ---
struct ContentView: View {
    @StateObject var viewModel = ChatViewModel()
    @State private var selectedConversationId: UUID? = nil
    
    var body: some View {
        NavigationSplitView {
            SidebarView(viewModel: viewModel, selectedConversationId: $selectedConversationId)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 0))
        } detail: {
            if let conversationId = selectedConversationId {
                ChatPanelView(conversationId: conversationId, viewModel: viewModel)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 0))
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "message.badge.circle")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text("Select a conversation")
                        .font(.title2)
                        .fontWeight(.medium)
                    Text("Choose a chat from the sidebar to start messaging")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 0))
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
    @State private var showingAccountMenu = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
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
                        .background(Color.blue.opacity(0.15))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            Divider().opacity(0.3)
            
            // Conversations List
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.conversations.values)) { conversation in
                        ConversationRowView(
                            conversation: conversation, 
                            viewModel: viewModel, 
                            selectedConversationId: $selectedConversationId
                        )
                    }
                }
                .padding(.vertical, 8)
            }
            
            Spacer()
            
            // Account Menu (placeholder)
            VStack(spacing: 0) {
                Divider().opacity(0.3)
                
                Button(action: { showingAccountMenu.toggle() }) {
                    HStack(spacing: 12) {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Account")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.primary)
                            Text("Settings & Profile")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(Color.secondary.opacity(0.05))
            }
        }
        .frame(minWidth: 260, maxWidth: 320)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 0))
        .popover(isPresented: $showingAccountMenu) {
            AccountMenuView()
                .frame(width: 250, height: 200)
                .background(.ultraThinMaterial)
        }
    }
}

// --- Account Menu Placeholder ---
struct AccountMenuView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Account")
                .font(.title3)
                .fontWeight(.semibold)
                .padding(.horizontal, 16)
                .padding(.top, 16)
            
            VStack(spacing: 12) {
                AccountMenuItem(icon: "person.circle", title: "Profile", subtitle: "Coming soon")
                AccountMenuItem(icon: "creditcard", title: "Billing", subtitle: "Coming soon")
                AccountMenuItem(icon: "key", title: "API Keys", subtitle: "Coming soon")
                AccountMenuItem(icon: "arrow.right.square", title: "Sign Out", subtitle: "Coming soon")
            }
            .padding(.horizontal, 16)
            
            Spacer()
        }
    }
}

struct AccountMenuItem: View {
    let icon: String
    let title: String
    let subtitle: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.secondary)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            // Placeholder action
        }
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
            Image(systemName: "message.circle")
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
                .fill(selectedConversationId == conversation.id ? .blue.opacity(0.15) : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.blue.opacity(0.3), lineWidth: selectedConversationId == conversation.id ? 1 : 0)
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
    @State private var editingNodeId: UUID? = nil
    @State private var editingText: String = ""
    @State private var hoveredNodeId: UUID? = nil
    @State private var showNodeTree = false
    @State private var canSendMessage = true
    
    var body: some View {
        ScrollViewReader { proxy in
            ZStack {
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Text(viewModel.conversations[conversationId]?.name ?? "Unknown")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Spacer()
                        
                        Button(action: { showingSettings = true }) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 16))
                                .foregroundColor(.blue)
                                .padding(8)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: { showNodeTree.toggle() }) {
                            Image(systemName: "rectangle.3.offgrid.bubble.left")
                                .font(.system(size: 16))
                                .foregroundColor(.secondary)
                                .padding(8)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding()
                    .background(.ultraThinMaterial.opacity(0.5))
                    
                    Divider().opacity(0.3)
                    
                    // Messages
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            let conversationPath = viewModel.getConversationPath(for: conversationId)
                            
                            if conversationPath.isEmpty {
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
                                ForEach(conversationPath) { node in
                                    NodeMessageView(
                                        node: node,
                                        conversationId: conversationId,
                                        viewModel: viewModel,
                                        editingNodeId: $editingNodeId,
                                        editingText: $editingText,
                                        hoveredNodeId: $hoveredNodeId,
                                        onEditSubmit: { newText in
                                            viewModel.editMessage(conversationId: conversationId, nodeId: node.id, newText: newText)
                                            if !node.isCurrentUser {
                                                // If editing AI message, get new response
                                                getAIResponse(for: newText, parentNodeId: node.parentId)
                                            }
                                        },
                                        onGetResponse: { userMessage in
                                            getAIResponse(for: userMessage, parentNodeId: node.id)
                                        }
                                    )
                                    .id(node.id)
                                }
                            }
                        }
                        .padding(.vertical, 20)
                    }
                    
                    Divider().opacity(0.3)
                    
                    // Input Area
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
                    .background(.ultraThinMaterial.opacity(0.8))
                }
                
                if showNodeTree {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .onTapGesture { showNodeTree = false }
                    
                    NodeTreeOverlay(
                        conversationId: conversationId,
                        viewModel: viewModel,
                        onNodeSelect: { nodeId in
                            viewModel.jumpToNode(conversationId: conversationId, nodeId: nodeId)
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
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 0))
            .sheet(isPresented: $showingSettings) {
                AISettingsView(viewModel: viewModel)
                    .frame(minWidth: 600, minHeight: 500)
            }
        }
    }
    
    private func sendMessage() {
        guard canSendMessage else { return }
        let trimmedMessage = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else { return }
        
        canSendMessage = false
        viewModel.addMessage(trimmedMessage, to: conversationId, isUser: true)
        messageText = ""
        
        // Get AI response
        getAIResponse(for: trimmedMessage, parentNodeId: viewModel.conversations[conversationId]?.currentNodeId)
    }
    
    private func getAIResponse(for userMessage: String, parentNodeId: UUID?) {
        isLoading = true
        viewModel.isTyping = true
        
        guard let url = URL(string: "http://127.0.0.1:1234/v1/chat/completions") else {
            addErrorResponse("Invalid API URL", to: parentNodeId)
            return
        }
        
        let conversationPath = viewModel.getConversationPath(for: conversationId)
        var messages: [[String: String]] = []
        
        // Add system prompt
        messages.append([
            "role": "system",
            "content": viewModel.aiSettings.systemPrompt
        ])
        
        // Add conversation history
        for node in conversationPath.suffix(10) {
            messages.append([
                "role": node.isCurrentUser ? "user" : "assistant",
                "content": node.label
            ])
            
            // Add AI responses if available
            if !node.isCurrentUser, let selectedResponseId = node.selectedResponseId,
               let response = node.aiResponses.first(where: { $0.id == selectedResponseId }) {
                messages.append([
                    "role": "assistant",
                    "content": response.text
                ])
            }
        }
        
        // Add current user message if not already in path
        if !conversationPath.last?.label.contains(userMessage) ?? true {
            messages.append([
                "role": "user",
                "content": userMessage
            ])
        }
        
        let requestBody: [String: Any] = [
            "model": viewModel.aiSettings.model,
            "messages": messages,
            "temperature": viewModel.aiSettings.temperature,
            "max_tokens": viewModel.aiSettings.maxTokens,
            "stream": false,
            "top_p": viewModel.aiSettings.topP,
            "frequency_penalty": viewModel.aiSettings.frequencyPenalty,
            "presence_penalty": viewModel.aiSettings.presencePenalty
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            addErrorResponse("Failed to encode request", to: parentNodeId)
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isLoading = false
                viewModel.isTyping = false
                canSendMessage = true
            }
            
            guard let data = data, error == nil else {
                addErrorResponse("Network error: \(error?.localizedDescription ?? "Unknown error")", to: parentNodeId)
                return
            }
            
            do {
                // Try OpenAI format first
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let firstChoice = choices.first,
                   let message = firstChoice["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    
                    let cleanContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    DispatchQueue.main.async {
                        if let nodeId = parentNodeId {
                            viewModel.addAIResponse(to: conversationId, nodeId: nodeId, response: cleanContent)
                        }
                    }
                    return
                }
                
                // Try other formats...
                addErrorResponse("Unexpected response format", to: parentNodeId)
                
            } catch {
                addErrorResponse("Failed to parse response: \(error.localizedDescription)", to: parentNodeId)
            }
        }.resume()
    }
    
    private func addErrorResponse(_ error: String, to nodeId: UUID?) {
        DispatchQueue.main.async {
            isLoading = false
            viewModel.isTyping = false
            canSendMessage = true
            
            if let nodeId = nodeId {
                viewModel.addAIResponse(to: conversationId, nodeId: nodeId, response: "Error: \(error)")
            }
        }
    }
}

// --- NodeMessageView ---
struct NodeMessageView: View {
    let node: ConversationNode
    let conversationId: UUID
    @ObservedObject var viewModel: ChatViewModel
    @Binding var editingNodeId: UUID?
    @Binding var editingText: String
    @Binding var hoveredNodeId: UUID?
    let onEditSubmit: (String) -> Void
    let onGetResponse: (String) -> Void
    
    var body: some View {
        VStack(spacing: 8) {
            // User Message
            HStack(alignment: .top, spacing: 4) {
                if node.isCurrentUser {
                    Spacer(minLength: 120)
                }
                
                VStack(alignment: node.isCurrentUser ? .trailing : .leading, spacing: 4) {
                    if editingNodeId == node.id {
                        TextField("Edit message", text: $editingText, onCommit: {
                            let trimmed = editingText.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty {
                                onEditSubmit(trimmed)
                            }
                            editingNodeId = nil
                        })
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                        .frame(maxWidth: 300)
                        .onAppear { editingText = node.label }
                    } else {
                        HStack {
                            if !node.isCurrentUser {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 12))
                                    .foregroundColor(.blue)
                            }
                            
                            Text(node.label)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(node.isCurrentUser ? .blue : .ultraThinMaterial)
                                .foregroundColor(node.isCurrentUser ? .white : .primary)
                                .cornerRadius(18)
                                .textSelection(.enabled)
                        }
                        
                        if hoveredNodeId == node.id {
                            HStack(spacing: 8) {
                                Button(action: {
                                    NSPasteboard.general.setString(node.label, forType: .string)
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
                                    editingNodeId = node.id
                                    editingText = node.label
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
                        
                        Text(formatTime(node.timestamp))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        hoveredNodeId = hovering ? node.id : nil
                    }
                }
                
                if !node.isCurrentUser {
                    Spacer(minLength: 120)
                }
            }
            
            // AI Responses
            if !node.aiResponses.isEmpty {
                HStack(alignment: .top, spacing: 4) {
                    VStack(alignment: .leading, spacing: 8) {
                        if let selectedResponseId = node.selectedResponseId,
                           let selectedResponse = node.aiResponses.first(where: { $0.id == selectedResponseId }) {
                            
                            HStack {
                                Image(systemName: "cpu")
                                    .font(.system(size: 12))
                                    .foregroundColor(.green)
                                
                                Text(selectedResponse.text)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(.ultraThinMaterial)
                                    .foregroundColor(.primary)
                                    .cornerRadius(18)
                                    .textSelection(.enabled)
                            }
                            
                            if node.aiResponses.count > 1 {
                                HStack(spacing: 8) {
                                    Text("Response \((node.aiResponses.firstIndex(where: { $0.id == selectedResponseId }) ?? 0) + 1) of \(node.aiResponses.count)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    
                                    HStack(spacing: 4) {
                                        ForEach(node.aiResponses.indices, id: \.self) { idx in
                                            Button(action: {
                                                viewModel.selectAIResponse(
                                                    conversationId: conversationId,
                                                    nodeId: node.id,
                                                    responseId: node.aiResponses[idx].id
                                                )
                                            }) {
                                                Circle()
                                                    .fill(node.aiResponses[idx].id == selectedResponseId ? .blue : .secondary.opacity(0.3))
                                                    .frame(width: 8, height: 8)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 4)
                                .background(.ultraThinMaterial.opacity(0.5))
                                .cornerRadius(12)
                            }
                        }
                    }
                    
                    Spacer(minLength: 120)
                }
            }
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// --- NodeTreeOverlay ---
struct NodeTreeOverlay: View {
    let conversationId: UUID
    let viewModel: ChatViewModel
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
                        messages: viewModel.getConversationPath(for: conversationId),
                        viewModel: viewModel,
                        conversationId: conversationId,
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
    let messages: [ConversationNode]
    let viewModel: ChatViewModel
    let conversationId: UUID
    let onNodeSelect: (UUID) -> Void
    
    var body: some View {
        VStack(spacing: 60) {
            ForEach(Array(messages.enumerated()), id: \.element.id) { messageIndex, node in
                FlowchartNodeView(
                    node: node,
                    messageIndex: messageIndex,
                    isLast: messageIndex == messages.count - 1,
                    viewModel: viewModel,
                    conversationId: conversationId,
                    onNodeSelect: onNodeSelect
                )
            }
        }
    }
}

// --- FlowchartNodeView ---
struct FlowchartNodeView: View {
    let node: ConversationNode
    let messageIndex: Int
    let isLast: Bool
    let viewModel: ChatViewModel
    let conversationId: UUID
    let onNodeSelect: (UUID) -> Void
    
    var body: some View {
        VStack(spacing: 40) {
            VStack(spacing: 20) {
                // Main Node
                FlowchartMessageBox(
                    text: node.label,
                    title: node.routeLabel ?? "Node \(messageIndex + 1)",
                    isSelected: viewModel.conversations[conversationId]?.currentNodeId == node.id,
                    isUser: node.isCurrentUser,
                    onTap: {
                        onNodeSelect(node.id)
                    }
                )
                
                // AI Responses
                if !node.aiResponses.isEmpty {
                    HStack(spacing: 30) {
                        ForEach(Array(node.aiResponses.enumerated()), id: \.element.id) { responseIdx, response in
                            FlowchartMessageBox(
                                text: response.text,
                                title: "Response \(responseIdx + 1)",
                                isSelected: node.selectedResponseId == response.id,
                                isUser: false,
                                onTap: {
                                    viewModel.selectAIResponse(
                                        conversationId: conversationId,
                                        nodeId: node.id,
                                        responseId: response.id
                                    )
                                    onNodeSelect(node.id)
                                }
                            )
                        }
                    }
                }
                
                // Connection line to next node
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
                        .fill(isUser ? Color.blue.opacity(0.15) : Color.green.opacity(0.15))
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

// --- Enhanced AISettingsView ---
struct AISettingsView: View {
    @ObservedObject var viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section("System Configuration") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("System Prompt")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        TextEditor(text: $viewModel.aiSettings.systemPrompt)
                            .font(.system(size: 14, family: .monospaced))
                            .frame(minHeight: 120)
                            .padding(8)
                            .background(.ultraThinMaterial)
                            .cornerRadius(8)
                            .onChange(of: viewModel.aiSettings.systemPrompt) { _ in
                                viewModel.saveSettings()
                            }
                        
                        Text("This prompt defines the AI's personality and behavior")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("Model Settings") {
                    VStack(alignment: .leading, spacing: 16) {
                        // Temperature
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Temperature")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Spacer()
                                Text("\(viewModel.aiSettings.temperature, specifier: "%.2f")")
                                    .font(.subheadline)
                                    .foregroundColor(.blue)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(.blue.opacity(0.1))
                                    .cornerRadius(4)
                            }
                            
                            Slider(value: $viewModel.aiSettings.temperature, in: 0.0...2.0, step: 0.1)
                                .accentColor(.blue)
                                .onChange(of: viewModel.aiSettings.temperature) { _ in
                                    viewModel.saveSettings()
                                }
                            
                            Text("Controls randomness. Higher = more creative, lower = more focused")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Divider().opacity(0.5)
                        
                        // Max Tokens
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Max Tokens")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Spacer()
                                Text("\(viewModel.aiSettings.maxTokens)")
                                    .font(.subheadline)
                                    .foregroundColor(.green)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(.green.opacity(0.1))
                                    .cornerRadius(4)
                            }
                            
                            Slider(value: Binding(
                                get: { Double(viewModel.aiSettings.maxTokens) },
                                set: { viewModel.aiSettings.maxTokens = Int($0) }
                            ), in: 100...8000, step: 100)
                                .accentColor(.green)
                                .onChange(of: viewModel.aiSettings.maxTokens) { _ in
                                    viewModel.saveSettings()
                                }
                            
                            Text("Maximum length of AI responses")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Divider().opacity(0.5)
                        
                        // Top P
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Top P")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Spacer()
                                Text("\(viewModel.aiSettings.topP, specifier: "%.2f")")
                                    .font(.subheadline)
                                    .foregroundColor(.orange)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(.orange.opacity(0.1))
                                    .cornerRadius(4)
                            }
                            
                            Slider(value: $viewModel.aiSettings.topP, in: 0.1...1.0, step: 0.05)
                                .accentColor(.orange)
                                .onChange(of: viewModel.aiSettings.topP) { _ in
                                    viewModel.saveSettings()
                                }
                            
                            Text("Alternative to temperature. Controls diversity of word choices")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Divider().opacity(0.5)
                        
                        // Top K
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Top K")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Spacer()
                                Text("\(viewModel.aiSettings.topK)")
                                    .font(.subheadline)
                                    .foregroundColor(.purple)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(.purple.opacity(0.1))
                                    .cornerRadius(4)
                            }
                            
                            Slider(value: Binding(
                                get: { Double(viewModel.aiSettings.topK) },
                                set: { viewModel.aiSettings.topK = Int($0) }
                            ), in: 1...100, step: 1)
                                .accentColor(.purple)
                                .onChange(of: viewModel.aiSettings.topK) { _ in
                                    viewModel.saveSettings()
                                }
                            
                            Text("Limits vocabulary choices to top K most likely words")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Section("Penalties") {
                    VStack(alignment: .leading, spacing: 16) {
                        // Frequency Penalty
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Frequency Penalty")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Spacer()
                                Text("\(viewModel.aiSettings.frequencyPenalty, specifier: "%.2f")")
                                    .font(.subheadline)
                                    .foregroundColor(.red)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(.red.opacity(0.1))
                                    .cornerRadius(4)
                            }
                            
                            Slider(value: $viewModel.aiSettings.frequencyPenalty, in: -2.0...2.0, step: 0.1)
                                .accentColor(.red)
                                .onChange(of: viewModel.aiSettings.frequencyPenalty) { _ in
                                    viewModel.saveSettings()
                                }
                            
                            Text("Reduces repetition of frequently used words")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        // Presence Penalty
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Presence Penalty")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Spacer()
                                Text("\(viewModel.aiSettings.presencePenalty, specifier: "%.2f")")
                                    .font(.subheadline)
                                    .foregroundColor(.pink)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(.pink.opacity(0.1))
                                    .cornerRadius(4)
                            }
                            
                            Slider(value: $viewModel.aiSettings.presencePenalty, in: -2.0...2.0, step: 0.1)
                                .accentColor(.pink)
                                .onChange(of: viewModel.aiSettings.presencePenalty) { _ in
                                    viewModel.saveSettings()
                                }
                            
                            Text("Encourages discussing new topics")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Section("Model Configuration") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Model Name")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        TextField("Enter model name...", text: $viewModel.aiSettings.model)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 14, family: .monospaced))
                            .onChange(of: viewModel.aiSettings.model) { _ in
                                viewModel.saveSettings()
                            }
                        
                        Text("The AI model identifier for your local server")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section {
                    HStack {
                        Button("Reset to Defaults") {
                            viewModel.resetSettingsToDefault()
                        }
                        .foregroundColor(.red)
                        .padding(.vertical, 8)
                        
                        Spacer()
                        
                        Button("Export Settings") {
                            // Placeholder for export functionality
                        }
                        .foregroundColor(.blue)
                        .padding(.vertical, 8)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("AI Configuration")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .background(.ultraThinMaterial)
    }
}

// Helper views for better UI
struct TypingIndicatorView: View {
    @State private var phase: Int = 0
    @State private var timer: Timer?
    let dotCount = 3
    let dotSize: CGFloat = 8
    let dotSpacing: CGFloat = 6
    
    var body: some View {
        HStack(spacing: dotSpacing) {
            ForEach(0..<dotCount, id: \.self) { i in
                Circle()
                    .fill(Color.gray)
                    .frame(width: dotSize, height: dotSize)
                    .opacity(phase == i ? 1 : 0.4)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: phase)
            }
        }
        .onAppear {
            timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
                phase = (phase + 1) % dotCount
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }
} 
