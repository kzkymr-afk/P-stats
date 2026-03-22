#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Google スプレッドシートの「CSV エクスポート URL」相当の内容を文字列として取得する。

- 共有が「リンクを知っている全員」なら、従来どおり HTTP GET のみでよい。
- 共有を「制限付き」にした場合は、環境変数 GOOGLE_SERVICE_ACCOUNT_JSON に
  サービスアカウント鍵（JSON 文字列）を渡し、Sheets API v4 で値を読む。
  （スプレッドシートをそのサービスアカウントのメールアドレスに「閲覧者」で共有すること）
"""

from __future__ import annotations

import csv
import io
import json
import os
import re
from typing import Optional
from urllib.parse import parse_qs, urlparse

import requests

REQUEST_TIMEOUT = 20
SCOPE = "https://www.googleapis.com/auth/spreadsheets.readonly"
SERVICE_ACCOUNT_ENV = "GOOGLE_SERVICE_ACCOUNT_JSON"


def parse_spreadsheet_export_url(url: str) -> Optional[tuple[str, int]]:
    """
    https://docs.google.com/spreadsheets/d/{spreadsheetId}/export?...&gid={n}
    を解析する。一致しなければ None。
    """
    p = urlparse((url or "").strip())
    host = (p.hostname or "").lower()
    if host != "docs.google.com":
        return None
    parts = [x for x in p.path.split("/") if x]
    try:
        di = parts.index("d")
        spreadsheet_id = parts[di + 1]
    except (ValueError, IndexError):
        return None
    if len(parts) <= di + 2 or parts[di + 2] != "export":
        return None
    if not spreadsheet_id:
        return None
    qs = parse_qs(p.query)
    gids = qs.get("gid") or qs.get("Gid")
    if not gids:
        return None
    try:
        gid = int(gids[0])
    except ValueError:
        return None
    return spreadsheet_id, gid


def _a1_range_for_sheet_title(title: str) -> str:
    """Sheets API values.get 用のシート名（A1 のシート部分のみ）。"""
    if re.match(r"^[A-Za-z0-9_]+$", title):
        return title
    return "'" + title.replace("'", "''") + "'"


def _sheet_title_for_gid(spreadsheet_id: str, gid: int, token: str) -> str:
    meta_url = f"https://sheets.googleapis.com/v4/spreadsheets/{spreadsheet_id}"
    headers = {"Authorization": f"Bearer {token}"}
    r = requests.get(
        meta_url,
        params={"fields": "sheets(properties(sheetId,title))"},
        headers=headers,
        timeout=REQUEST_TIMEOUT,
    )
    r.raise_for_status()
    for sh in r.json().get("sheets", []):
        props = sh.get("properties") or {}
        if props.get("sheetId") == gid:
            t = props.get("title")
            if t:
                return t
    raise RuntimeError(
        f"シート gid={gid} が見つかりません。"
        "スプレッドシートをサービスアカウントのメールに共有しているか確認してください。"
    )


def _values_to_csv(values: list[list]) -> str:
    buf = io.StringIO()
    w = csv.writer(buf, lineterminator="\n")
    for row in values:
        w.writerow(row)
    return buf.getvalue()


def fetch_spreadsheet_csv_via_api(spreadsheet_id: str, gid: int, service_account_json: str) -> str:
    try:
        from google.auth.transport.requests import Request
        from google.oauth2 import service_account
    except ImportError as e:
        raise RuntimeError(
            "制限付きスプレッドシート取得には google-auth が必要です: pip install google-auth"
        ) from e

    info = json.loads(service_account_json)
    creds = service_account.Credentials.from_service_account_info(info, scopes=[SCOPE])
    creds.refresh(Request())
    token = creds.token or ""
    title = _sheet_title_for_gid(spreadsheet_id, gid, token)
    range_a1 = _a1_range_for_sheet_title(title)

    from urllib.parse import quote

    range_enc = quote(range_a1, safe="")
    values_url = f"https://sheets.googleapis.com/v4/spreadsheets/{spreadsheet_id}/values/{range_enc}"
    r = requests.get(
        values_url,
        headers={"Authorization": f"Bearer {token}"},
        timeout=REQUEST_TIMEOUT,
    )
    r.raise_for_status()
    values = r.json().get("values") or []
    return _values_to_csv(values)


def fetch_spreadsheet_csv(url: str, *, timeout: int = REQUEST_TIMEOUT) -> str:
    """
    Google の export URL なら Sheets API（サービスアカウント JSON があるとき）、
    それ以外は匿名 GET。401 のときは制限付き向けの案内を出す。
    """
    sa = (os.environ.get(SERVICE_ACCOUNT_ENV) or "").strip()
    parsed = parse_spreadsheet_export_url(url)

    if sa and parsed:
        spreadsheet_id, gid = parsed
        return fetch_spreadsheet_csv_via_api(spreadsheet_id, gid, sa)

    r = requests.get(url, timeout=timeout)
    if r.status_code == 401 and parsed:
        raise RuntimeError(
            "スプレッドシートが 401 Unauthorized です（制限付き共有の可能性）。"
            f"GitHub Actions の Repository secrets に {SERVICE_ACCOUNT_ENV} を登録し（サービスアカウント JSON 全文）、"
            "Google Cloud で Sheets API を有効化したうえで、スプレッドシートをそのサービスアカウントの"
            "メール（…@….iam.gserviceaccount.com）に閲覧者として共有してください。"
        )
    r.raise_for_status()
    r.encoding = "utf-8"
    raw = r.text
    if raw.startswith("\ufeff"):
        raw = raw[1:]

    if parsed and not sa:
        head = raw[:800].lower()
        if "<html" in head or "accounts.google.com" in head or "sign in" in head:
            raise RuntimeError(
                "スプレッドシートの応答が HTML（ログイン画面）です。共有を制限付きにした場合は "
                f"{SERVICE_ACCOUNT_ENV} による Sheets API 取得を設定してください。"
            )
    return raw
