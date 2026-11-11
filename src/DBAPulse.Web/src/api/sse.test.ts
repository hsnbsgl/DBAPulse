import { describe, expect, it } from 'vitest';
import { createSseParser, parseSseBlock, type SseEvent } from './sse';

describe('parseSseBlock', () => {
  it('reads event name and data', () => {
    expect(parseSseBlock('event: token\ndata: "Hello"')).toEqual({ event: 'token', data: '"Hello"' });
  });

  it('defaults the event name to message', () => {
    expect(parseSseBlock('data: hi')).toEqual({ event: 'message', data: 'hi' });
  });

  it('strips only one leading space after data:', () => {
    expect(parseSseBlock('data:   indented')?.data).toBe('  indented');
    expect(parseSseBlock('data:nospace')?.data).toBe('nospace');
  });

  it('joins multi-line data with newlines', () => {
    expect(parseSseBlock('event: token\ndata: line one\ndata:\ndata: line three')?.data).toBe('line one\n\nline three');
  });

  it('ignores comments and returns null without data', () => {
    expect(parseSseBlock(': keep-alive')).toBeNull();
    expect(parseSseBlock('event: token')).toBeNull();
  });

  it('handles CRLF line endings and trailing whitespace in data', () => {
    expect(parseSseBlock('event: token\r\ndata: a \r\ndata: b')).toEqual({ event: 'token', data: 'a \nb' });
  });
});

describe('createSseParser', () => {
  it('emits events split across chunks and flushes the remainder', () => {
    const events: SseEvent[] = [];
    const parser = createSseParser(event => events.push(event));
    parser.push('event: token\nda');
    parser.push('ta: "A"\n\nevent: token\r\ndata: "B"\r\n\r\nevent: done\ndata: ');
    expect(events).toEqual([{ event: 'token', data: '"A"' }, { event: 'token', data: '"B"' }]);
    parser.push('{}');
    parser.flush();
    expect(events[events.length - 1]).toEqual({ event: 'done', data: '{}' });
  });
});
