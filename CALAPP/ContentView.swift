//
//  ContentView.swift
//  CALAPP
//
//  Created by Michael Knaap on 05/06/2025.
//

import SwiftUI
import Foundation

struct Message: Identifiable, Codable {
    let id = UUID()
    let text: String
    let isCurrentUser: Bool
    let timestamp: Date
    
    init(text: String, isCurrentUser: Bool) {
        self.text = text
        self.isCurrentUser = isCurrentUser
        self.timestamp = Date()
    }
}

struct ContentView: View {
    @State private var selectedChat: String? = "General"
    
    var body: some View {
        NavigationSplitView {
            // Sidebar
            SidebarView(selectedChat: $selectedChat)
        } detail: {
            // Main chat panel
            ChatPanelView(chatName: selectedChat ?? "Select a chat")
        }
        .navigationSplitViewStyle(.balanced)
    }
}

struct SidebarView: View {
    @Binding var selectedChat: String?
    
    private let chatList = ["General", "Random", "Tech Talk", "Design", "Projects"]
    
    var body: some View {
        List(chatList, id: \.self, selection: $selectedChat) { chat in
            NavigationLink(value: chat) {
                HStack {
                    Image(systemName: "message.fill")
                        .foregroundColor(.blue)
                        .font(.system(size: 16))
                    Text(chat)
                        .font(.system(size: 15))
                }
                .padding(.vertical, 2)
            }
        }
        .navigationTitle("Chats")
        .frame(minWidth: 200)
    }
}

struct ChatPanelView: View {
    let chatName: String
    @State private var messageText = ""
    @State private var messages: [Message] = []
    @State private var isLoading = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Chat header
            HStack {
                Text(chatName)
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
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Chat messages area
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if messages.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "message")
                                    .font(.system(size: 40))
                                    .foregroundColor(.secondary)
                                Text("Welcome to \(chatName)")
                                    .font(.title3)
                                    .fontWeight(.medium)
                                Text("Start a conversation with the AI")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, 100)
                        } else {
                            ForEach(messages) { message in
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
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(18)
                                Spacer()
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onChange(of: messages.count) { _ in
                    if let lastMessage = messages.last {
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
                    .background(Color(NSColor.controlBackgroundColor))
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
        }
        .frame(minWidth: 400)
    }
    
    private func sendMessage() {
        let trimmedMessage = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else { return }
        
        // Add user message
        let userMessage = Message(text: trimmedMessage, isCurrentUser: true)
        messages.append(userMessage)
        messageText = ""
        
        // Get AI response
        getAIResponse(for: trimmedMessage)
    }
    
    private func getAIResponse(for userMessage: String) {
        isLoading = true
        
        guard let url = URL(string: "http://127.0.0.1:1234/v1/chat/completions") else {
            addErrorMessage("Invalid API URL")
            return
        }
        
        let requestBody: [String: Any] = [
            "model": "dolphin-2.9.4-llama3.1-8b",
            "messages": [
                [
                    "role": "user",
                    "content": userMessage
                ]
            ],
            "temperature": 0.7,
            "max_tokens": 500
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            addErrorMessage("Failed to encode request")
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isLoading = false
                
                if let error = error {
                    addErrorMessage("Network error: \(error.localizedDescription)")
                    return
                }
                
                guard let data = data else {
                    addErrorMessage("No response data")
                    return
                }
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let choices = json["choices"] as? [[String: Any]],
                       let firstChoice = choices.first,
                       let message = firstChoice["message"] as? [String: Any],
                       let content = message["content"] as? String {
                        
                        let aiMessage = Message(text: content.trimmingCharacters(in: .whitespacesAndNewlines), isCurrentUser: false)
                        messages.append(aiMessage)
                    } else {
                        addErrorMessage("Unexpected response format")
                    }
                } catch {
                    addErrorMessage("Failed to parse response")
                }
            }
        }.resume()
    }
    
    private func addErrorMessage(_ error: String) {
        let errorMessage = Message(text: "Error: \(error)", isCurrentUser: false)
        messages.append(errorMessage)
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

#Preview {
    ContentView()
        .frame(width: 800, height: 600)
}
