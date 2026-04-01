import Foundation

// MARK: - RFC 4180 風 CSV（引用・"" エスケープ・改行を含むフィールド）

enum RFC4180CSV {
    /// 1 フィールドずつ走査して行の配列に分割（改行をクォート内で許容）
    static func parseTables(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\"" {
                if inQuotes, i + 1 < chars.count, chars[i + 1] == "\"" {
                    field.append("\"")
                    i += 2
                    continue
                }
                inQuotes.toggle()
                i += 1
                continue
            }
            if !inQuotes, c == "," {
                row.append(field)
                field = ""
                i += 1
                continue
            }
            if !inQuotes, (c == "\n" || c == "\r") {
                if c == "\r", i + 1 < chars.count, chars[i + 1] == "\n" {
                    i += 1
                }
                row.append(field)
                field = ""
                if !row.allSatisfy({ $0.isEmpty }) {
                    rows.append(row)
                }
                row = []
                i += 1
                continue
            }
            field.append(c)
            i += 1
        }
        row.append(field)
        if !row.allSatisfy({ $0.isEmpty }) {
            rows.append(row)
        }
        return rows
    }

    static func stripUTF8BOM(_ data: Data) -> Data {
        if data.count >= 3, data[0] == 0xEF, data[1] == 0xBB, data[2] == 0xBF {
            return data.subdata(in: 3..<data.count)
        }
        return data
    }
}
