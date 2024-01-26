const defaultTheme = require('tailwindcss/defaultTheme')

module.exports = {
  content: ["../lib/**/*.*ex"],
  theme: {
    extend: {
      typography: {
        DEFAULT: {
          css: {
            code: {
              color: "var(--tw-prose-code)",
              backgroundColor: "var(--tw-prose-pre-code)",
              borderRadius: ".2em",
              fontWeight: "400",
              padding: ".1em .2em",
            },
            "code::before": {
              content: "",
            },
            "code::after": {
              content: "",
            },
          },
        },
      },
      fontFamily: {
        sans: ["Inter", ...defaultTheme.fontFamily.sans],
      },
    }
  },
  plugins: [
    require("@tailwindcss/typography")
  ]
}
