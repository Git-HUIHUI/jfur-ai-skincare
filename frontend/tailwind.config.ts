import type { Config } from "tailwindcss"

const config: Config = {
  content: [
    "./app/**/*.{js,ts,jsx,tsx,mdx}",
    "./components/**/*.{js,ts,jsx,tsx,mdx}",
  ],
  theme: {
    extend: {
      colors: {
        brand: {
          50: "#f0f7ff",
          100: "#e0effe",
          200: "#baddfd",
          300: "#7ec2fc",
          400: "#3aa3f8",
          500: "#1088e9",
          600: "#046bc7",
          700: "#0555a1",
          800: "#094985",
          900: "#0d3d6e",
        },
        jfur: {
          primary: "#2B5F8A",
          accent: "#D4A853",
          light: "#F7F3EB",
          dark: "#1A3A56",
        }
      },
      fontFamily: {
        sans: ["var(--font-sans)", "system-ui", "sans-serif"],
      },
    },
  },
  plugins: [],
};
export default config;
