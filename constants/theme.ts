export const COLORS = {
  primary: '#38ef7d', // Bright Teal/Green (High visibility on dark)
  primaryDark: '#11998e', // Darker Teal for gradients
  secondary: '#FFD700', // Gold/Yellow (Accent)
  background: '#0f2027', // Deep Dark Blue/Black
  backgroundGradient: ['#0f2027', '#203a43', '#2c5364'], // Standard Gradient
  card: 'rgba(255, 255, 255, 0.1)', // Glassmorphic Card
  white: '#FFFFFF',
  text: '#FFFFFF',
  textSecondary: 'rgba(255, 255, 255, 0.7)',
  textLight: 'rgba(255, 255, 255, 0.5)',
  success: '#4ADE80', // Bright Green
  warning: '#FFC107', // Amber
  error: '#EF4444', // Red
  border: 'rgba(255, 255, 255, 0.2)',
  transparent: 'transparent',
} as const;

export const SPACING = {
  xs: 4,
  s: 8,
  m: 16,
  l: 24,
  xl: 32,
  xxl: 48,
};

export const SHADOWS = {
  small: {
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.3, // Darker shadow for dark mode
    shadowRadius: 4,
    elevation: 3,
  },
  medium: {
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 5 },
    shadowOpacity: 0.4,
    shadowRadius: 10,
    elevation: 6,
  },
  glow: {
    shadowColor: '#38ef7d',
    shadowOffset: { width: 0, height: 0 },
    shadowOpacity: 0.6,
    shadowRadius: 10,
    elevation: 5,
  },
};
