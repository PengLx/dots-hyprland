-- 输入法 (fcitx5) —— 见 CUSTOMIZATIONS.md
hl.env("QT_IM_MODULE", "fcitx")
hl.env("XMODIFIERS", "@im=fcitx")
hl.env("SDL_IM_MODULE", "fcitx")
hl.env("GLFW_IM_MODULE", "ibus")   -- GLFW 应用走 ibus 垫片;fcitx 的 GLFW 支持不稳
hl.env("INPUT_METHOD", "fcitx")
