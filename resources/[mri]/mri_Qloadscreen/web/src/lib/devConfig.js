// Browser-only stand-in for the server config (vite dev and headless prints).
export const DEV_CONFIG = {
  texts: {
    title: 'VERTIGO ROLEPLAY',
    subtitle: 'Sua história começa aqui.',
    loading: 'CARREGANDO...',
    discord: 'Entre agora!',
  },
  logo: { file: 'vertigo_logo.png', width: 160 },
  discordUrl: 'https://discord.mriqbox.com.br',
  overlay: true,
  showHints: true,
  volume: 0.1,
  staff: { enabled: true, members: [] },
  tracks: [
    { video: 'https://r2.fivemanage.com/NPYjK3TScd7LGsz8PIbt3/GTA6.mp4', useVideoAudio: true, audio: '', title: 'GTA6', artist: 'Rockstar Games' },
  ],
}
