/* Буфер обміну сеансу на Android — лише текст, через застосунок: процес сеансу до системного буфера
 * Android доступу не має, тож буфер телефона читає й пише застосунок, а сюди приходить і звідси
 * йде тільки текст (MSG_CLIP_TEXT / EVT_CLIP_TEXT, UTF-8).
 *
 * Телефон → сервер: застосунок надсилає свій текст (коли повертаються в MHRD) → серверу список
 * форматів з CF_UNICODETEXT; сервер просить дані — віддаємо збережений текст.
 * Сервер → телефон: сервер оголосив текст → одразу просимо його (лише текст, до 1 МБ) і віддаємо
 * застосунку, той кладе в буфер телефона.
 */
#include "clipboard.h"

#include <stdlib.h>
#include <string.h>

#include <winpr/string.h>
#include <winpr/synch.h>
#include <winpr/user.h>

#include "proto.h"

#define CLIP_TEXT_MAX (1024u * 1024)

struct MhrdClipboard
{
	CRITICAL_SECTION lock;
	CliprdrClientContext* cliprdr; /* NULL, поки канал не підключено */
	char* local;                   /* текст із буфера телефона (UTF-8), NULL — немає */
};

static CliprdrClientContext* get_cliprdr(MhrdClipboard* cb)
{
	EnterCriticalSection(&cb->lock);
	CliprdrClientContext* c = cb->cliprdr;
	LeaveCriticalSection(&cb->lock);
	return c;
}

static void send_format_list(MhrdClipboard* cb)
{
	CliprdrClientContext* c = get_cliprdr(cb);
	if (!c)
		return;
	EnterCriticalSection(&cb->lock);
	const BOOL has = cb->local && *cb->local;
	LeaveCriticalSection(&cb->lock);
	CLIPRDR_FORMAT formats[1] = { 0 };
	formats[0].formatId = CF_UNICODETEXT;
	CLIPRDR_FORMAT_LIST list = { 0 };
	list.common.msgType = CB_FORMAT_LIST;
	list.numFormats = has ? 1 : 0;
	list.formats = formats;
	c->ClientFormatList(c, &list);
}

/* UTF-8 з LF → UTF-16LE з CRLF і нулем у кінці (як чекає Windows). */
static BYTE* to_unicodetext(const char* text, UINT32* outLen)
{
	const size_t n = strlen(text);
	char* crlf = malloc(n * 2 + 1);
	if (!crlf)
		return NULL;
	size_t o = 0;
	for (size_t i = 0; i < n; i++)
	{
		if (text[i] == '\n' && (i == 0 || text[i - 1] != '\r'))
			crlf[o++] = '\r';
		crlf[o++] = text[i];
	}
	crlf[o] = 0;
	size_t wlen = 0;
	WCHAR* w = ConvertUtf8ToWCharAlloc(crlf, &wlen);
	free(crlf);
	if (!w)
		return NULL;
	*outLen = (UINT32)((wlen + 1) * sizeof(WCHAR));
	return (BYTE*)w;
}

static UINT on_server_format_data_request(CliprdrClientContext* c, const CLIPRDR_FORMAT_DATA_REQUEST* req)
{
	MhrdClipboard* cb = (MhrdClipboard*)c->custom;
	CLIPRDR_FORMAT_DATA_RESPONSE resp = { 0 };
	resp.common.msgType = CB_FORMAT_DATA_RESPONSE;
	resp.common.msgFlags = CB_RESPONSE_FAIL;
	BYTE* data = NULL;
	UINT32 len = 0;
	if (req->requestedFormatId == CF_UNICODETEXT)
	{
		EnterCriticalSection(&cb->lock);
		if (cb->local)
			data = to_unicodetext(cb->local, &len);
		LeaveCriticalSection(&cb->lock);
	}
	if (data)
	{
		resp.common.msgFlags = CB_RESPONSE_OK;
		resp.common.dataLen = len;
		resp.requestedFormatData = data;
	}
	const UINT rc = c->ClientFormatDataResponse(c, &resp);
	free(data);
	return rc;
}

/* Сервер оголосив свій буфер: є текст — одразу просимо його. */
static UINT on_server_format_list(CliprdrClientContext* c, const CLIPRDR_FORMAT_LIST* list)
{
	BOOL text = FALSE;
	for (UINT32 i = 0; i < list->numFormats; i++)
		text |= list->formats[i].formatId == CF_UNICODETEXT;
	CLIPRDR_FORMAT_LIST_RESPONSE resp = { 0 };
	resp.common.msgType = CB_FORMAT_LIST_RESPONSE;
	resp.common.msgFlags = CB_RESPONSE_OK;
	UINT rc = c->ClientFormatListResponse(c, &resp);
	if (rc == CHANNEL_RC_OK && text)
	{
		CLIPRDR_FORMAT_DATA_REQUEST req = { 0 };
		req.common.msgType = CB_FORMAT_DATA_REQUEST;
		req.requestedFormatId = CF_UNICODETEXT;
		rc = c->ClientFormatDataRequest(c, &req);
	}
	return rc;
}

/* Текст із сервера → застосунку (UTF-8, CRLF → LF). */
static UINT on_server_format_data_response(CliprdrClientContext* c, const CLIPRDR_FORMAT_DATA_RESPONSE* resp)
{
	(void)c;
	if (!(resp->common.msgFlags & CB_RESPONSE_OK) || !resp->requestedFormatData || resp->common.dataLen < 2 ||
	    resp->common.dataLen > CLIP_TEXT_MAX * 2)
		return CHANNEL_RC_OK;
	const WCHAR* w = (const WCHAR*)resp->requestedFormatData;
	const size_t chars = _wcsnlen(w, resp->common.dataLen / sizeof(WCHAR));
	size_t n = 0;
	char* utf8 = ConvertWCharNToUtf8Alloc(w, chars, &n);
	if (!utf8)
		return CHANNEL_RC_OK;
	size_t o = 0;
	for (size_t i = 0; i < n; i++)
	{
		if (utf8[i] == '\r' && i + 1 < n && utf8[i + 1] == '\n')
			continue;
		utf8[o++] = utf8[i];
	}
	if (o <= CLIP_TEXT_MAX)
		proto_send(EVT_CLIP_TEXT, utf8, (uint32_t)o);
	free(utf8);
	return CHANNEL_RC_OK;
}

static UINT on_monitor_ready(CliprdrClientContext* c, const CLIPRDR_MONITOR_READY* ready)
{
	(void)ready;
	CLIPRDR_GENERAL_CAPABILITY_SET general = { 0 };
	general.capabilitySetType = CB_CAPSTYPE_GENERAL;
	general.capabilitySetLength = CB_CAPSTYPE_GENERAL_LEN;
	general.version = CB_CAPS_VERSION_2;
	general.generalFlags = CB_USE_LONG_FORMAT_NAMES;
	CLIPRDR_CAPABILITIES caps = { 0 };
	caps.cCapabilitiesSets = 1;
	caps.capabilitySets = (CLIPRDR_CAPABILITY_SET*)&general;
	const UINT rc = c->ClientCapabilities(c, &caps);
	if (rc == CHANNEL_RC_OK)
		send_format_list((MhrdClipboard*)c->custom); /* що вже скопійовано на телефоні */
	return rc;
}

static UINT on_ok(CliprdrClientContext* c, const void* any)
{
	(void)c;
	(void)any;
	return CHANNEL_RC_OK;
}

static UINT on_server_capabilities(CliprdrClientContext* c, const CLIPRDR_CAPABILITIES* caps)
{
	return on_ok(c, caps);
}

static UINT on_server_format_list_response(CliprdrClientContext* c, const CLIPRDR_FORMAT_LIST_RESPONSE* resp)
{
	return on_ok(c, resp);
}

MhrdClipboard* clipboard_new(void)
{
	MhrdClipboard* cb = calloc(1, sizeof(MhrdClipboard));
	if (cb)
		InitializeCriticalSection(&cb->lock);
	return cb;
}

void clipboard_attach(MhrdClipboard* cb, CliprdrClientContext* cliprdr)
{
	cliprdr->custom = cb;
	cliprdr->MonitorReady = on_monitor_ready;
	cliprdr->ServerCapabilities = on_server_capabilities;
	cliprdr->ServerFormatList = on_server_format_list;
	cliprdr->ServerFormatListResponse = on_server_format_list_response;
	cliprdr->ServerFormatDataRequest = on_server_format_data_request;
	cliprdr->ServerFormatDataResponse = on_server_format_data_response;
	EnterCriticalSection(&cb->lock);
	cb->cliprdr = cliprdr;
	LeaveCriticalSection(&cb->lock);
}

void clipboard_detach(MhrdClipboard* cb)
{
	EnterCriticalSection(&cb->lock);
	cb->cliprdr = NULL;
	LeaveCriticalSection(&cb->lock);
}

void clipboard_set_text(MhrdClipboard* cb, const char* utf8, size_t len)
{
	if (!cb || len > CLIP_TEXT_MAX)
		return;
	char* copy = malloc(len + 1);
	if (!copy)
		return;
	memcpy(copy, utf8, len);
	copy[len] = 0;
	EnterCriticalSection(&cb->lock);
	free(cb->local);
	cb->local = copy;
	LeaveCriticalSection(&cb->lock);
	send_format_list(cb);
}

void clipboard_free(MhrdClipboard* cb)
{
	if (!cb)
		return;
	clipboard_detach(cb);
	free(cb->local);
	DeleteCriticalSection(&cb->lock);
	free(cb);
}
