const displayTimeZone = import.meta.env.VITE_DISPLAY_TIMEZONE || 'Europe/Istanbul';

export const formatDateTime = (value?: string | null) => value
  ? new Intl.DateTimeFormat('tr-TR', {
      timeZone: displayTimeZone,
      dateStyle: 'short',
      timeStyle: 'medium',
    }).format(new Date(value))
  : 'N/A';