---------------------------------------------------------------------------
--- Titlebars for awful.
--
-- @author Uli Schlachter
-- @copyright 2012 Uli Schlachter
-- @release @AWESOME_VERSION@
-- @module awful.titlebar
---------------------------------------------------------------------------

local error = error
local type = type
local util = require("awful.util")
local abutton = require("awful.button")
local aclient = require("awful.client")
local atooltip = require("awful.tooltip")
local beautiful = require("beautiful")
local drawable = require("wibox.drawable")
local imagebox = require("wibox.widget.imagebox")
local textbox = require("wibox.widget.textbox")
local base = require("wibox.widget.base")
local capi = {
    client = client
}
local titlebar = {
    widget = {}
}

--- Set a declarative widget hierarchy description.
-- See [The declarative layout system](../documentation/03-declarative-layout.md.html)
-- @param args An array containing the widgets disposition
-- @name setup
-- @class function

--- Show tooltips when hover on titlebar buttons (defaults to 'true')
titlebar.enable_tooltip = true

local all_titlebars = setmetatable({}, { __mode = 'k' })

-- Get a color for a titlebar, this tests many values from the array and the theme
local function get_color(name, c, args)
    local suffix = "_normal"
    if capi.client.focus == c then
        suffix = "_focus"
    end
    local function get(array)
        return array["titlebar_"..name..suffix] or array["titlebar_"..name] or array[name..suffix] or array[name]
    end
    return get(args) or get(beautiful)
end

local function get_titlebar_function(c, position)
    if position == "left" then
        return c.titlebar_left
    elseif position == "right" then
        return c.titlebar_right
    elseif position == "top" then
        return c.titlebar_top
    elseif position == "bottom" then
        return c.titlebar_bottom
    else
        error("Invalid titlebar position '" .. position .. "'")
    end
end

--- Get a client's titlebar
-- @class function
-- @param c The client for which a titlebar is wanted.
-- @param[opt] args A table with extra arguments for the titlebar. The
-- "size" is the height of the titlebar. Available "position" values are top,
-- left, right and bottom. Additionally, the foreground and background colors
-- can be configured via e.g. "bg_normal" and "bg_focus".
-- @name titlebar
local function new(c, args)
    args = args or {}
    local position = args.position or "top"
    local size = args.size or util.round(beautiful.get_font_height(args.font) * 1.5)
    local d = get_titlebar_function(c, position)(c, size)

    -- Make sure that there is never more than one titlebar for any given client
    local bars = all_titlebars[c]
    if not bars then
        bars = {}
        all_titlebars[c] = bars
    end

    local ret
    if not bars[position] then
        local context = {
            client = c,
            position = position
        }
        ret = drawable(d, context, "awful.titlebar")
        local function update_colors()
            local args_ = bars[position].args
            ret:set_bg(get_color("bg", c, args_))
            ret:set_fg(get_color("fg", c, args_))
            ret:set_bgimage(get_color("bgimage", c, args_))
        end

        bars[position] = {
            args = args,
            drawable = ret,
            update_colors = update_colors
        }

        -- Update the colors when focus changes
        c:connect_signal("focus", update_colors)
        c:connect_signal("unfocus", update_colors)
    else
        bars[position].args = args
        ret = bars[position].drawable
    end

    -- Make sure the titlebar has the right colors applied
    bars[position].update_colors()

    -- Handle declarative/recursive widget container
    ret.setup = base.widget.setup

    return ret
end

--- Show a client's titlebar.
-- @param c The client whose titlebar is modified
-- @param[opt] position The position of the titlebar. Must be one of "left",
--   "right", "top", "bottom". Default is "top".
function titlebar.show(c, position)
    position = position or "top"
    local bars = all_titlebars[c]
    local data = bars and bars[position]
    local args = data and data.args
    new(c, args)
end

--- Hide a client's titlebar.
-- @param c The client whose titlebar is modified
-- @param[opt] position The position of the titlebar. Must be one of "left",
--   "right", "top", "bottom". Default is "top".
function titlebar.hide(c, position)
    position = position or "top"
    get_titlebar_function(c, position)(c, 0)
end

--- Toggle a client's titlebar, hiding it if it is visible, otherwise showing it.
-- @param c The client whose titlebar is modified
-- @param[opt] position The position of the titlebar. Must be one of "left",
--   "right", "top", "bottom". Default is "top".
function titlebar.toggle(c, position)
    position = position or "top"
    local _, size = get_titlebar_function(c, position)(c)
    if size == 0 then
        titlebar.show(c, position)
    else
        titlebar.hide(c, position)
    end
end

--- Create a new titlewidget. A title widget displays the name of a client.
-- Please note that this returns a textbox and all of textbox' API is available.
-- This way, you can e.g. modify the font that is used.
-- @param c The client for which a titlewidget should be created.
-- @return The title widget.
function titlebar.widget.titlewidget(c)
    local ret = textbox()
    local function update()
        ret:set_text(c.name or "<unknown>")
    end
    c:connect_signal("property::name", update)
    update()

    return ret
end

--- Create a new icon widget. An icon widget displays the icon of a client.
-- Please note that this returns an imagebox and all of the imagebox' API is
-- available. This way, you can e.g. disallow resizes.
-- @param c The client for which an icon widget should be created.
-- @return The icon widget.
function titlebar.widget.iconwidget(c)
    local ret = imagebox()
    local function update()
        ret:set_image(c.icon)
    end
    c:connect_signal("property::icon", update)
    update()

    return ret
end

--- Create a new button widget. A button widget displays an image and reacts to
-- mouse clicks. Please note that the caller has to make sure that this widget
-- gets redrawn when needed by calling the returned widget's update() function.
-- The selector function should return a value describing a state. If the value
-- is a boolean, either "active" or "inactive" are used. The actual image is
-- then found in the theme as "titlebar_[name]_button_[normal/focus]_[state]".
-- If that value does not exist, the focused state is ignored for the next try.
-- @param c The client for which a button is created.
-- @tparam string name Name of the button, used for accessing the theme and
--   in the tooltip.
-- @param selector A function that selects the image that should be displayed.
-- @param action Function that is called when the button is clicked.
-- @return The widget
function titlebar.widget.button(c, name, selector, action)
    local ret = imagebox()

    if titlebar.enable_tooltip then
        ret.tooltip = atooltip({ objects = {ret}, delay_show = 1 })
        ret.tooltip:set_text(name)
    end

    local function update()
        local img = selector(c)
        if type(img) ~= "nil" then
            -- Convert booleans automatically
            if type(img) == "boolean" then
                if img then
                    img = "active"
                else
                    img = "inactive"
                end
            end
            -- First try with a prefix based on the client's focus state
            local prefix = "normal"
            if capi.client.focus == c then
                prefix = "focus"
            end
            if img ~= "" then
                prefix = prefix .. "_"
            end
            local theme = beautiful["titlebar_" .. name .. "_button_" .. prefix .. img]
            if not theme then
                -- Then try again without that prefix if nothing was found
                theme = beautiful["titlebar_" .. name .. "_button_" .. img]
            end
            if theme then
                img = theme
            end
        end
        ret:set_image(img)
    end
    if action then
        ret:buttons(abutton({ }, 1, nil, function() action(c, selector(c)) end))
    end

    ret.update = update
    update()

    -- We do magic based on whether a client is focused above, so we need to
    -- connect to the corresponding signal here.
    c:connect_signal("focus", update)
    c:connect_signal("unfocus", update)

    return ret
end

--- Create a new float button for a client.
-- @param c The client for which the button is wanted.
function titlebar.widget.floatingbutton(c)
    local widget = titlebar.widget.button(c, "floating", aclient.object.get_floating, aclient.floating.toggle)
    c:connect_signal("property::floating", widget.update)
    return widget
end

--- Create a new maximize button for a client.
-- @param c The client for which the button is wanted.
function titlebar.widget.maximizedbutton(c)
    local widget = titlebar.widget.button(c, "maximized", function(cl)
        return cl.maximized_horizontal or cl.maximized_vertical
    end, function(cl, state)
        cl.maximized_horizontal = not state
        cl.maximized_vertical = not state
    end)
    c:connect_signal("property::maximized_vertical", widget.update)
    c:connect_signal("property::maximized_horizontal", widget.update)
    return widget
end

--- Create a new minimize button for a client.
-- @param c The client for which the button is wanted.
function titlebar.widget.minimizebutton(c)
    local widget = titlebar.widget.button(c, "minimize", function(cl) return cl.minimized end, function(cl) cl.minimized = not cl.minimized end)
    c:connect_signal("property::minimized", widget.update)
    return widget
end

--- Create a new closing button for a client.
-- @param c The client for which the button is wanted.
function titlebar.widget.closebutton(c)
    return titlebar.widget.button(c, "close", function() return "" end, function(cl) cl:kill() end)
end

--- Create a new ontop button for a client.
-- @param c The client for which the button is wanted.
function titlebar.widget.ontopbutton(c)
    local widget = titlebar.widget.button(c, "ontop", function(cl) return cl.ontop end, function(cl, state) cl.ontop = not state end)
    c:connect_signal("property::ontop", widget.update)
    return widget
end

--- Create a new sticky button for a client.
-- @param c The client for which the button is wanted.
function titlebar.widget.stickybutton(c)
    local widget = titlebar.widget.button(c, "sticky", function(cl) return cl.sticky end, function(cl, state) cl.sticky = not state end)
    c:connect_signal("property::sticky", widget.update)
    return widget
end

client.connect_signal("unmanage", function(c)
    all_titlebars[c] = nil
end)

return setmetatable(titlebar, { __call = function(_, ...) return new(...) end})

-- vim: filetype=lua:expandtab:shiftwidth=4:tabstop=8:softtabstop=4:textwidth=80
