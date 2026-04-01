//
//  CsvSessionImportTests.swift
//

import Testing
@testable import P_stats

struct CsvSessionImportTests {

    @Test func rfc4180PreservesCommaInsideQuotes() {
        let csv = "a,b\n\"c,d\",e\n"
        let rows = RFC4180CSV.parseTables(csv)
        #expect(rows.count == 2)
        #expect(rows[1][0] == "c,d")
        #expect(rows[1][1] == "e")
    }

    @Test func parseMinimalSessionsRows() throws {
        let csv = """
        date_iso8601,inputCash,totalHoldings,machineName,shopName
        2025-01-01T12:00:00Z,1000,5000,テスト機,テスト店
        """
        let rows = try CsvSessionImportService.parseSessionsTable(csv)
        #expect(rows.count == 1)
        #expect(rows[0].canImport == true)
        #expect(rows[0].csvMachineName == "テスト機")
        #expect(rows[0].csvShopName == "テスト店")
    }

    @Test func parseRecoveryPtInsteadOfHoldings() throws {
        let csv = """
        date,inputCash,recovery_pt,machineName,shopName
        2025-06-01T10:00:00+09:00,2000,8000,機種A,店B
        """
        let rows = try CsvSessionImportService.parseSessionsTable(csv)
        #expect(rows.count == 1)
        #expect(rows[0].canImport == true)
    }
}
