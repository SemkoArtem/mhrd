/* Канал між застосунком MHRD і процесом mhrd-session (SPEC → «Архітектура»).
 *
 * Кадр: u32 LE довжина (1 байт типу + дані), u8 тип, дані.
 * stdin — повідомлення від застосунку, stdout — події до нього. Журнали FreeRDP ідуть у stderr.
 * Числа в даних — little-endian. Той самий формат описано в lib/sessions/session_protocol.dart.
 */
#pragma once

#include <stdint.h>
#include <winpr/wtypes.h>

enum
{
	/* застосунок -> mhrd-session */
	MSG_CONNECT = 0x01,      /* JSON з налаштуваннями й паролем */
	MSG_KEY = 0x02,          /* u16 скан-код (біт 8 = розширений), u8 натиснуто */
	MSG_MOUSE_MOVE = 0x03,   /* u16 x, u16 y */
	MSG_MOUSE_BUTTON = 0x04, /* u8 кнопка (1 ліва, 2 права, 3 середня), u8 натиснуто, u16 x, u16 y */
	MSG_MOUSE_WHEEL = 0x05,  /* i16 крок (+120 = від себе), u8 горизонтально, u16 x, u16 y */
	MSG_CERT_ANSWER = 0x06,  /* u8 довіряти */
	MSG_DISCONNECT = 0x07,
	MSG_RESIZE = 0x08,       /* u16 ширина, u16 висота — нова роздільність (канал Display Control) */
	MSG_FOCUS = 0x09,        /* показати власне вікно сеансу (режим nativeWindow) */

	/* mhrd-session -> застосунок */
	EVT_STATE = 0x81,        /* u8 стан: 1 з'єднання, 2 підключено */
	EVT_SURFACE = 0x82,      /* u32 ширина, u32 висота, u32 крок рядка, ім'я спільної пам'яті */
	EVT_FRAME = 0x83,        /* u32 x, y, w, h — ділянка оновилась */
	EVT_CERTIFICATE = 0x84,  /* JSON: host, port, commonName, subject, issuer, fingerprint, flags, changed */
	EVT_DISCONNECTED = 0x85, /* u8 категорія, u32 код FreeRDP, текст помилки */
};

/* Категорії відключення — однакові з DisconnectReason у Dart. */
enum
{
	DISC_USER_REQUEST = 0,
	DISC_NETWORK = 1,
	DISC_AUTH_FAILED = 2,
	DISC_NO_CREDENTIALS = 3,
	DISC_ACCOUNT_LOCKED = 4,
	DISC_PASSWORD_EXPIRED = 5,
	DISC_CERT_REJECTED = 6,
	DISC_TLS = 7,
	DISC_SERVER_LOGOFF = 8,
	DISC_OTHER_CONNECTION = 9,
	DISC_SERVER_DENIED = 10,
	DISC_OTHER = 11,
};

#ifdef _MSC_VER
#pragma warning(disable : 4200) /* гнучкий масив у кінці структури — стандартний C99 */
#endif

typedef struct ProtoMsg
{
	struct ProtoMsg* next;
	uint8_t type;
	uint32_t len;
	uint8_t data[];
} ProtoMsg;

/* Двійковий режим stdin/stdout і потік читання stdin. */
BOOL proto_init(void);

/* Подія, що сигналізує: у черзі є повідомлення або stdin закрито. */
HANDLE proto_event(void);

/* Наступне повідомлення або NULL. Звільняти через free(). */
ProtoMsg* proto_pop(void);

/* Чекає повідомлення до timeoutMs; NULL — час вийшов або stdin закрито. */
ProtoMsg* proto_wait(DWORD timeoutMs);

/* Застосунок закрив канал (наприклад, сам завершився) — сеанс має закритися. */
BOOL proto_closed(void);

/* Надсилає подію; безпечно з будь-якого потоку. */
void proto_send(uint8_t type, const void* data, uint32_t len);

static inline void put_u32(uint8_t* p, uint32_t v)
{
	p[0] = (uint8_t)v;
	p[1] = (uint8_t)(v >> 8);
	p[2] = (uint8_t)(v >> 16);
	p[3] = (uint8_t)(v >> 24);
}

static inline uint16_t get_u16(const uint8_t* p)
{
	return (uint16_t)(p[0] | (p[1] << 8));
}
