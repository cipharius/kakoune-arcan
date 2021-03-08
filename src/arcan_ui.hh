#ifndef arcan_ui_hh_INCLUDED
#define arcan_ui_hh_INCLUDED

#include <stdint.h>
#include <limits.h>

#include "user_interface.hh"
#include "display_buffer.hh"
#include "event_manager.hh"
#include "coord.hh"
#include "string.hh"
#include "user_interface.hh"
#include "keys.hh"

namespace Kakoune
{

extern "C"
{
#define _Static_assert(...)
#define arcan_tui_ucs4utf8(...) arcan_tui_ucs4utf8(uint32_t, char dst[4])
#define arcan_tui_ucs4utf8_s(...) arcan_tui_ucs4utf8_s(uint32_t, char dst[5])
#define arcan_tui_utf8ucs4(...) arcan_tui_utf8ucs4(const char src[4], uint32_t* dst)
#include <arcan/shmif/arcan_shmif.h>
#include <arcan/arcan_tui.h>
#undef arcan_tui_ucs4utf8
#undef arcan_tui_ucs4utf8_s
#undef arcan_tui_utf8ucs4
#undef _Static_assert
}

class ArcanUI : public UserInterface, public Singleton<ArcanUI>
{
public:
    ArcanUI();
    ~ArcanUI() override;

    ArcanUI(const ArcanUI&) = delete;
    ArcanUI& operator=(const ArcanUI&) = delete;

    bool is_ok() const override { return m_state.is_ok; };

    void menu_show(ConstArrayView<DisplayLine> choices,
                   DisplayCoord anchor, Face fg, Face bg,
                   MenuStyle style) override;
    void menu_select(int selected) override;
    void menu_hide() override;

    void info_show(const DisplayLine& title,
                   const DisplayLineList& content,
                   DisplayCoord anchor, Face face,
                   InfoStyle style) override;
    void info_hide() override;

    void draw(const DisplayBuffer& display_buffer,
              const Face& default_face,
              const Face& padding_face) override;

    void draw_status(const DisplayLine& status_line,
                     const DisplayLine& mode_line,
                     const Face& default_face) override;

    DisplayCoord dimensions() override;

    void set_cursor(CursorMode mode, DisplayCoord coord) override;

    void refresh(bool force) override;

    void set_on_key(OnKeyCallback callback) override;

    void set_ui_options(const Options& options) override;

    void tick(Timer& timer);

    struct WindowState
    {
        bool is_ok = true;
        bool resize_pending = false;
        OnKeyCallback on_key;
    };

    WindowState m_state;

private:
    tui_cbcfg setup_callbacks();
    void draw(ConstArrayView<DisplayAtom> atoms, const Face& default_face);

    const std::unordered_map<uint32_t, Codepoint> m_tui_key_codepoint;
    Timer m_tick;
    arcan_tui_conn* m_conn;
    tui_context* m_window;
};

}

#endif // arcan_ui_hh_INCLUDED
