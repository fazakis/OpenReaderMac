import Foundation

struct SSHConfiguration {
    let connection: Connection
    var destination: String { connection.sshUser.isEmpty ? connection.sshHost : "\(connection.sshUser)@\(connection.sshHost)" }
    var validationMessage: String? {
        let c = connection
        guard !c.sshHost.isEmpty else { return "Enter an SSH alias or host in Connection settings. Your server details stay on this Mac." }
        guard c.sshHost.range(of: "^[A-Za-z0-9_][A-Za-z0-9_.:-]*$", options: .regularExpression) != nil,
              c.sshUser.isEmpty || c.sshUser.range(of: "^[A-Za-z0-9_][A-Za-z0-9_.-]*$", options: .regularExpression) != nil else {
            return "Use an SSH alias or host without spaces. Leave SSH user empty to use the User entry in ~/.ssh/config."
        }
        guard (1024...65535).contains(c.localPort), let url = URL(string: c.serverURL),
              ["http", "https"].contains(url.scheme ?? ""), ["127.0.0.1", "localhost"].contains(url.host ?? ""),
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil, url.port == c.localPort else {
            return "For managed SSH, use a loopback API URL such as http://127.0.0.1:<local port>/v1 with the matching local port."
        }
        return nil
    }
    var arguments: [String] {
        ["-N", "-T", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes", "-o", "ExitOnForwardFailure=yes",
         "-o", "ConnectTimeout=10", "-o", "ServerAliveInterval=15", "-o", "ServerAliveCountMax=2",
         "-L", "127.0.0.1:\(connection.localPort):127.0.0.1:8880", destination]
    }
}
