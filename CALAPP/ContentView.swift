//
//  ContentView.swift
//  CALAPP
//
//  Created by Michael Knaap on 05/06/2025.
//

import SwiftUI
import Foundation

struct Message: Identifiable, Codable {
    var id = UUID()
    let text: String
    let isCurrentUser: Bool
    let timestamp: Date
    
    init(text: String, isCurrentUser: Bool) {
        self.text = text
        self.isCurrentUser = isCurrentUser
        self.timestamp = Date()
    }
}

struct Conversation: Identifiable, Codable {
    let id = UUID()
    var name: String
    var messages: [Message]
    let createdAt: Date
    
    init(name: String) {
        self.name = name
        self.messages = []
        self.createdAt = Date()
    }
    
    var lastMessagePreview: String {
        guard let lastMessage = messages.last else { return "No messages" }
        return lastMessage.text.prefix(50) + (lastMessage.text.count > 50 ? "..." : "")
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }
}

class ChatViewModel: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var selectedConversationId: UUID?
    
    var selectedConversation: Conversation? {
        conversations.first { $0.id == selectedConversationId }
    }
    
    init() {
        // Start with one default conversation
        createNewConversation(name: "General Chat")
    }
    
    func createNewConversation(name: String) {
        let newConversation = Conversation(name: name)
        conversations.append(newConversation)
        selectedConversationId = newConversation.id
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
    }
    
    func addMessage(_ message: Message, to conversationId: UUID) {
        if let index = conversations.firstIndex(where: { $0.id == conversationId }) {
            conversations[index].messages.append(message)
        }
    }
    
    func getMessages(for conversationId: UUID) -> [Message] {
        return conversations.first { $0.id == conversationId }?.messages ?? []
    }
    
    func getConversationName(for conversationId: UUID) -> String {
        return conversations.first { $0.id == conversationId }?.name ?? "Unknown"
    }
}

struct ContentView: View {
    @StateObject private var viewModel = ChatViewModel()
    
    var body: some View {
        NavigationSplitView {
            // Sidebar
            SidebarView(viewModel: viewModel)
        } detail: {
            // Main chat panel
            if let selectedId = viewModel.selectedConversationId {
                ChatPanelView(conversationId: selectedId, viewModel: viewModel)
            } else {
                VStack {
                    Image(systemName: "message")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    Text("Select a conversation or create a new one")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
}

struct SidebarView: View {
    @ObservedObject var viewModel: ChatViewModel
    @State private var showingNewChatAlert = false
    @State private var newChatName = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with New Chat button
            HStack {
                Text("Conversations")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button(action: { showingNewChatAlert = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .opacity(0.95)
            )
            
            Divider()
            
            // Conversations List
            List(viewModel.conversations, selection: $viewModel.selectedConversationId) { conversation in
                ConversationRowView(conversation: conversation, viewModel: viewModel)
                    .listRowBackground(Color.clear)
            }
            .listStyle(.sidebar)
        }
        .frame(minWidth: 250)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(0.95)
                .background(
                    BlurView(style: .contentBackground)
                        .opacity(0.7)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .alert("New Conversation", isPresented: $showingNewChatAlert) {
            TextField("Conversation name", text: $newChatName)
            Button("Create") {
                if !newChatName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    viewModel.createNewConversation(name: newChatName.trimmingCharacters(in: .whitespacesAndNewlines))
                    newChatName = ""
                }
            }
            Button("Cancel", role: .cancel) {
                newChatName = ""
            }
        } message: {
            Text("Enter a name for your new conversation")
        }
    }
}

struct ConversationRowView: View {
    let conversation: Conversation
    @ObservedObject var viewModel: ChatViewModel
    @State private var showingRenameAlert = false
    @State private var newName = ""
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(conversation.name)
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(1)
                
                Text(conversation.lastMessagePreview)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                Text(conversation.formattedDate)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .opacity(0.7)
            }
            
            Spacer()
            
            Menu {
                Button("Rename") {
                    newName = conversation.name
                    showingRenameAlert = true
                }
                
                if viewModel.conversations.count > 1 {
                    Button("Delete", role: .destructive) {
                        viewModel.deleteConversation(id: conversation.id)
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.selectedConversationId = conversation.id
        }
        .alert("Rename Conversation", isPresented: $showingRenameAlert) {
            TextField("New name", text: $newName)
            Button("Rename") {
                if !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    viewModel.renameConversation(id: conversation.id, newName: newName.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
            Button("Cancel", role: .cancel) { }
        }
    }
}

struct ChatPanelView: View {
    let conversationId: UUID
    @ObservedObject var viewModel: ChatViewModel
    @State private var messageText = ""
    @State private var isLoading = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Chat header
            HStack {
                Text(viewModel.getConversationName(for: conversationId))
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button(action: {}) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .opacity(0.95)
                    .background(
                        BlurView(style: .contentBackground)
                            .opacity(0.7)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            
            Divider()
            
            // Chat messages area
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if viewModel.getMessages(for: conversationId).isEmpty {
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
                        } else {
                            ForEach(viewModel.getMessages(for: conversationId)) { message in
                                MessageBubbleView(message: message)
                                    .id(message.id)
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
                                .background(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(.ultraThinMaterial)
                                        .opacity(0.85)
                                        .background(
                                            BlurView(style: .contentBackground)
                                                .opacity(0.6)
                                        )
                                )
                                Spacer()
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onChange(of: viewModel.getMessages(for: conversationId).count) {
                    if let lastMessage = viewModel.getMessages(for: conversationId).last {
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            Divider()
            
            // Message input
            HStack(spacing: 12) {
                TextField("Message", text: $messageText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .opacity(0.9)
                            .background(
                                BlurView(style: .sidebar)
                                    .opacity(0.5)
                            )
                    )
                    .cornerRadius(20)
                    .lineLimit(1...4)
                    .onSubmit {
                        sendMessage()
                    }
                
                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary : .blue)
                }
                .buttonStyle(.plain)
                .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .opacity(0.95)
                    .background(
                        BlurView(style: .contentBackground)
                            .opacity(0.7)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .frame(minWidth: 400)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(0.95)
                .background(
                    BlurView(style: .contentBackground)
                        .opacity(0.8)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }
    
    private func sendMessage() {
        let trimmedMessage = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else { return }
        
        // Add user message
        let userMessage = Message(text: trimmedMessage, isCurrentUser: true)
        viewModel.addMessage(userMessage, to: conversationId)
        messageText = ""
        
        // Get AI response
        getAIResponse(for: trimmedMessage)
    }
    
    private func getAIResponse(for userMessage: String) {
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
        
        // Add system prompt to make AI smarter
        messages.append([
            "role": "system",
            "content": "You are a helpful, intelligent, and creative AI assistant. Provide thoughtful, detailed, and engaging responses. Be concise when appropriate but don't hesitate to elaborate when helpful. Always be friendly and professional."
        ])
        
        // Add recent conversation history (last 10 messages for context)
        let recentMessages = conversationHistory.suffix(10)
        for message in recentMessages {
            if message.text.starts(with: "Error:") { continue } // Skip error messages
            messages.append([
                "role": message.isCurrentUser ? "user" : "assistant",
                "content": message.text
            ])
        }
        
        // Add current message if not already included
        if messages.last?["content"] != userMessage {
            messages.append([
                "role": "user",
                "content": userMessage
            ])
        }
        
        let requestBody: [String: Any] = [
            "model": "dolphin-2.9.4-llama3.1-8b",
            "messages": messages,
            "temperature": 0.8,
            "max_tokens": 2000,
            "stream": false,
            "top_p": 0.9,
            "frequency_penalty": 0.1,
            "presence_penalty": 0.1
        ]
        
        print("📝 Request body created with \(messages.count) messages")
        
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
                
                // Print raw response for debugging
                if let responseString = String(data: data, encoding: .utf8) {
                    print("📄 Raw response: \(responseString)")
                }
                
                do {
                    // Try OpenAI-compatible format first
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let choices = json["choices"] as? [[String: Any]],
                       let firstChoice = choices.first,
                       let message = firstChoice["message"] as? [String: Any],
                       let content = message["content"] as? String {
                        
                        print("✅ Successfully parsed OpenAI format response")
                        let aiMessage = Message(text: content.trimmingCharacters(in: .whitespacesAndNewlines), isCurrentUser: false)
                        viewModel.addMessage(aiMessage, to: conversationId)
                        return
                    }
                    
                    // Try direct response format
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let response = json["response"] as? String {
                        print("✅ Successfully parsed direct response format")
                        let aiMessage = Message(text: response.trimmingCharacters(in: .whitespacesAndNewlines), isCurrentUser: false)
                        viewModel.addMessage(aiMessage, to: conversationId)
                        return
                    }
                    
                    // Try completion format
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let completion = json["completion"] as? String {
                        print("✅ Successfully parsed completion format")
                        let aiMessage = Message(text: completion.trimmingCharacters(in: .whitespacesAndNewlines), isCurrentUser: false)
                        viewModel.addMessage(aiMessage, to: conversationId)
                        return
                    }
                    
                    // Try text format
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let text = json["text"] as? String {
                        print("✅ Successfully parsed text format")
                        let aiMessage = Message(text: text.trimmingCharacters(in: .whitespacesAndNewlines), isCurrentUser: false)
                        viewModel.addMessage(aiMessage, to: conversationId)
                        return
                    }
                    
                    // If we get here, we couldn't parse the response
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
        let errorMessage = Message(text: "Error: \(error)", isCurrentUser: false)
        viewModel.addMessage(errorMessage, to: conversationId)
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

#Preview {
    ContentView()
        .frame(width: 800, height: 600)
}
