#include "arcan_ui.hh"

#include <iostream>
#include <unordered_map>

namespace Kakoune
{

const std::unordered_map<uint32_t, Codepoint> m_tui_key_codepoint =
{
    {TUIK_BACKSPACE, Key::NamedKey::Backspace},
    {TUIK_DELETE,    Key::NamedKey::Delete},
    {TUIK_ESCAPE,    Key::NamedKey::Escape},
    {TUIK_RETURN,    Key::NamedKey::Return},
    {TUIK_UP,        Key::NamedKey::Up},
    {TUIK_DOWN,      Key::NamedKey::Down},
    {TUIK_LEFT,      Key::NamedKey::Left},
    {TUIK_RIGHT,     Key::NamedKey::Right},
    {TUIK_PAGEUP,    Key::NamedKey::PageUp},
    {TUIK_PAGEDOWN,  Key::NamedKey::PageDown},
    {TUIK_HOME,      Key::NamedKey::Home},
    {TUIK_END,       Key::NamedKey::End},
    {TUIK_INSERT,    Key::NamedKey::Insert},
    {TUIK_TAB,       Key::NamedKey::Tab},
    {TUIK_F1,        Key::NamedKey::F1},
    {TUIK_F2,        Key::NamedKey::F2},
    {TUIK_F3,        Key::NamedKey::F3},
    {TUIK_F4,        Key::NamedKey::F4},
    {TUIK_F5,        Key::NamedKey::F5},
    {TUIK_F6,        Key::NamedKey::F6},
    {TUIK_F7,        Key::NamedKey::F7},
    {TUIK_F8,        Key::NamedKey::F8},
    {TUIK_F9,        Key::NamedKey::F9},
    {TUIK_F10,       Key::NamedKey::F10},
    {TUIK_F11,       Key::NamedKey::F11},
    {TUIK_F12,       Key::NamedKey::F12},
};

ArcanUI::WindowState* cast_tag(void* tag)
{
    return static_cast<ArcanUI::WindowState*>(tag);
}

tui_screen_attr arcan_face(const Face& face)
{
    auto attr = face.attributes;
    uint16_t aflags
        = (attr & Attribute::Underline) ? TUI_ATTR_UNDERLINE : 0
        | (attr & Attribute::Reverse)   ? TUI_ATTR_INVERSE   : 0
        | (attr & Attribute::Blink)     ? TUI_ATTR_BLINK     : 0
        | (attr & Attribute::Bold)      ? TUI_ATTR_BOLD      : 0
        | (attr & Attribute::Italic)    ? TUI_ATTR_ITALIC    : 0;
    struct tui_screen_attr screen_attr = {
        .fc = {face.fg.r, face.fg.g, face.fg.b},
        .bc = {face.bg.r, face.bg.g, face.bg.b},
        .aflags = aflags
    };
    return screen_attr;
}

void tui_resized(struct tui_context* c,
                 size_t neww, size_t newh,
                 size_t cols, size_t rows, void* tag)
{
    auto& state = *(cast_tag(tag));
    state.resize_pending = true;
}

bool tui_input_utf8(struct tui_context* c,
                    const char* u8, size_t len, void* tag)
{
    auto& state = *(cast_tag(tag));
    Codepoint key = utf8::read_codepoint(u8, u8 + len);

    // Leave special keys for tui_input_key
    if (key >= 32)
    {
        state.on_key(key);
        return true;
    }
    else
    {
        return false;
    }
}

void tui_input_key(struct tui_context* c,
                   uint32_t symest, uint8_t scancode,
                   uint8_t mods, uint16_t subid, void* tag)
{
    auto& state = *(cast_tag(tag));
    auto symbol = m_tui_key_codepoint.find(symest);
    if (symbol != m_tui_key_codepoint.end())
        state.on_key(symbol->second);
}

tui_cbcfg ArcanUI::setup_callbacks()
{
    struct tui_cbcfg cbcfg = {
        .tag = &m_state,
        .input_utf8 = tui_input_utf8,
        .input_key = tui_input_key,
        .resized = tui_resized
    };
    return cbcfg;
}

void timer_callback(Timer& timer)
{
    ArcanUI::instance().tick(timer);
    timer.set_next_date(Clock::now() + std::chrono::milliseconds(33));
}

ArcanUI::ArcanUI()
: m_tick(Clock::now() + std::chrono::milliseconds(33), timer_callback)
{
    m_conn = arcan_tui_open_display("Kakoune", "");
    struct tui_cbcfg cbcfg = setup_callbacks();
    m_window = arcan_tui_setup(m_conn, NULL, &cbcfg, sizeof(cbcfg));
    arcan_tui_set_flags(m_window, TUI_MOUSE_FULL | TUI_HIDE_CURSOR);
}

ArcanUI::~ArcanUI()
{
    arcan_tui_destroy(m_window, NULL);
}

void ArcanUI::menu_show(ConstArrayView<DisplayLine> choices,
                        DisplayCoord anchor, Face fg, Face bg,
                        MenuStyle style)
{
}

void ArcanUI::tick(Timer& timer)
{
    if (arcan_tui_process(&m_window, 1, NULL, 0, -1).errc != TUI_ERRC_OK)
        m_state.is_ok = false;

    if (m_state.resize_pending) {
        size_t rows, cols;
        arcan_tui_dimensions(m_window, &rows, &cols);
        m_state.on_key(resize(DisplayCoord(rows, cols)));
        m_state.resize_pending = false;
    }
}

void ArcanUI::menu_select(int selected)
{
}

void ArcanUI::menu_hide()
{
}

void ArcanUI::info_show(const DisplayLine& title,
                        const DisplayLineList& content,
                        DisplayCoord anchor, Face face,
                        InfoStyle style)
{
}

void ArcanUI::info_hide()
{
}

void ArcanUI::draw(const DisplayBuffer& display_buffer,
                   const Face& default_face,
                   const Face& padding_face)
{
    tui_screen_attr screen_attr = arcan_face(default_face);

    size_t rows, cols;
    arcan_tui_dimensions(m_window, &rows, &cols);

    LineCount line_index = 0;
    for (const DisplayLine& line : display_buffer.lines())
    {
        arcan_tui_eraseattr_region(m_window, 0, (int)line_index,
                                   cols, (int)line_index,
                                   false, screen_attr);
        arcan_tui_move_to(m_window, 0, (int)line_index);
        this->draw(line.atoms(), default_face);
        line_index++;
    }

    auto face = merge_faces(default_face, padding_face);
    arcan_tui_eraseattr_region(m_window, 0, (int)line_index,
                               cols, rows,
                               false, arcan_face(face));
    while (line_index < rows)
    {
        arcan_tui_move_to(m_window, 0, (int)line_index);
        this->draw(DisplayAtom("~"), face);
        line_index++;
    }
}

void ArcanUI::draw_status(const DisplayLine& status_line,
                          const DisplayLine& mode_line,
                          const Face& default_face)
{
    size_t rows, cols;
    arcan_tui_dimensions(m_window, &rows, &cols);
    tui_screen_attr screen_attr = arcan_face(default_face);

    arcan_tui_eraseattr_region(m_window,
                               0, rows-1, cols, rows-1,
                               false, screen_attr);
    arcan_tui_move_to(m_window, 0, rows);
    this->draw(status_line.atoms(), default_face);

    const auto mode_len = mode_line.length();
    const auto status_len = status_line.length();
    const auto remaining = cols - status_len;

    if (mode_len < remaining)
    {
        arcan_tui_move_to(m_window, cols - (int)mode_len, rows-1);
        this->draw(mode_line.atoms(), default_face);
    }
}

DisplayCoord ArcanUI::dimensions()
{
    size_t rows, cols;
    arcan_tui_dimensions(m_window, &rows, &cols);
    return DisplayCoord(rows, cols);
}

void ArcanUI::set_cursor(CursorMode mode, DisplayCoord coord)
{
}

void ArcanUI::refresh(bool force)
{
    if (force)
        arcan_tui_invalidate(m_window);

    arcan_tui_refresh(m_window);
}

void ArcanUI::set_on_key(OnKeyCallback callback)
{
    m_state.on_key = callback;
}

void ArcanUI::set_ui_options(const Options& options)
{
}

void ArcanUI::draw(ConstArrayView<DisplayAtom> atoms, const Face& default_face)
{
    for (const DisplayAtom& atom : atoms)
    {
        tui_screen_attr face = arcan_face(merge_faces(default_face, atom.face));
        arcan_tui_writestr(m_window, atom.content().str().c_str(), &face);
    }
}

}
