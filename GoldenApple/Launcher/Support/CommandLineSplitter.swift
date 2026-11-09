import Foundation

/// Splits text into arguments like a shell does: whitespace separates arguments,
/// single quotes keep text as is, double quotes keep spaces and allow `\"` and `\\`,
/// and a backslash outside quotes escapes the next character.
/// An unclosed quote runs to the end of the text.
nonisolated enum CommandLineSplitter {
    static func split(_ text: String) -> [String] {
        var arguments: [String] = []
        var current = ""
        var hasArgument = false
        var quote: Character?
        var pendingBackslash = false

        for character in text {
            if pendingBackslash {
                let isQuotedEscape = character == "\"" || character == "\\"
                if quote == "\"" && !isQuotedEscape {
                    current.append("\\")
                }
                current.append(character)
                pendingBackslash = false
                continue
            }
            switch (quote, character) {
            case ("'", "'"), ("\"", "\""):
                quote = nil
            case ("\"", "\\"), (nil, "\\"):
                pendingBackslash = true
                hasArgument = true
            case ("'", _), ("\"", _):
                current.append(character)
            case (nil, "'"), (nil, "\""):
                quote = character
                hasArgument = true
            case (nil, _) where character.isWhitespace:
                if hasArgument {
                    arguments.append(current)
                    current = ""
                    hasArgument = false
                }
            default:
                current.append(character)
                hasArgument = true
            }
        }
        if pendingBackslash {
            current.append("\\")
        }
        if hasArgument {
            arguments.append(current)
        }
        return arguments
    }
}
