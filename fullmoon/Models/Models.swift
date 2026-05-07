//
//  Models.swift
//  Navi
//
//  Replaces fullmoon's MLX-based Models.swift with NaviModelConfig-based configuration.
//

import Foundation

/// Model type classification (kept for compatibility with reasoning model handling)
enum NaviModelType {
    case regular, reasoning
}

extension NaviModel {
    var modelType: NaviModelType {
        // All current Navi models are regular (non-reasoning)
        return .regular
    }
    
    /// Build prompt history from thread messages in the model's expected format
    func getPromptHistory(thread: Thread, systemPrompt: String) -> [[String: String]] {
        var history: [[String: String]] = []
        
        // System prompt
        history.append([
            "role": "system",
            "content": systemPrompt,
        ])
        
        // Messages
        for message in thread.sortedMessages {
            let role = message.role.rawValue
            var content = message.content
            
            // If message has image, add placeholder text
            if message.imageData != nil {
                content = "[用户发送了一张图片]\n\(content)"
            }
            
            history.append([
                "role": role,
                "content": content,
            ])
        }
        
        return history
    }
}
