import Foundation
import TVRemoteCore

/// Error text shared by the apps and the intent runner.
enum ErrorText {
    static func describe(_ error: Error) -> String {
        if let error = error as? TVControllerError, let text = error.errorDescription {
            return text
        }
        return error.localizedDescription
    }
}
