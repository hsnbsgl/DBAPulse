export type SseEvent = { event: string; data: string };

/** Parses one SSE event block. Per the SSE spec, a single leading space after "data:" is removed and multi-line data is joined with "\n". */
export const parseSseBlock = (block: string): SseEvent | null => {
  let event = 'message';
  const data: string[] = [];
  for (const line of block.split(/\r\n|\r|\n/)) {
    if (!line || line.startsWith(':')) continue;
    const colon = line.indexOf(':');
    const field = colon === -1 ? line : line.slice(0, colon);
    let value = colon === -1 ? '' : line.slice(colon + 1);
    if (value.startsWith(' ')) value = value.slice(1);
    if (field === 'event') event = value;
    else if (field === 'data') data.push(value);
  }
  return data.length ? { event, data: data.join('\n') } : null;
};

/** Incremental SSE parser: push decoded text chunks, receive complete events. Call flush() at end of stream. */
export const createSseParser = (onEvent: (event: SseEvent) => void) => {
  let buffer = '';
  const emit = (block: string) => { const parsed = parseSseBlock(block); if (parsed) onEvent(parsed); };
  return {
    push(chunk: string) {
      buffer += chunk;
      const blocks = buffer.split(/\r?\n\r?\n/);
      buffer = blocks.pop() || '';
      blocks.forEach(emit);
    },
    flush() { if (buffer) emit(buffer); buffer = ''; },
  };
};
