// -*- Mode: vala; indent-tabs-mode: nil; tab-width: 4 -*-
/*-
 * Copyright (c) 2015 Pantheon Developers (https://launchpad.net/switchboard-plug-printers)
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Library General Public License for more details.
 *
 * You should have received a copy of the GNU Library General Public
 * License along with this library; if not, write to the
 * Free Software Foundation, Inc., 59 Temple Place - Suite 330,
 * Boston, MA 02111-1307, USA.
 *
 * Authored by: Corentin Noël <corentin@elementary.io>
 */

namespace Printers {

    public static Plug plug;

    public class Plug : Switchboard.Plug {
        Gtk.Paned main_paned;
        public static const uint RENEW_INTERVAL = 500;
        public static const int SUBSCRIPTION_DURATION = 600;
        private int subscription_id = -1;

        public Plug () {
            Object (category: Category.HARDWARE,
                    code_name: Build.PLUGCODENAME,
                    display_name: _("Printers"),
                    description: _("Configure printers, manage print queues, and view ink levels"),
                    icon: "printer");
            plug = this;
        }

        public override Gtk.Widget get_widget () {
            if (main_paned == null) {
                main_paned = new Gtk.Paned (Gtk.Orientation.HORIZONTAL);
                var stack = new Gtk.Stack ();
                var list = new PrinterList ();
                main_paned.pack1 (list, false, false);
                main_paned.pack2 (stack, true, false);
                list.new_printer_page.connect ((w) => {
                    stack.add (w);
                });

                list.focused_printer_page.connect ((w) => {
                    stack.set_visible_child (w);
                });

                unowned CUPS.Destination[] dests = CUPS.get_destinations ();
                Printer default_printer = null;
                foreach (unowned CUPS.Destination dest in dests) {
                    var printer = new Printer (dest);
                    if (default_printer == null && printer.is_default) {
                        default_printer = printer;
                    }

                    list.add_printer (printer);
                }

                unowned Cups.Notifier notifier = Cups.Notifier.get_default ();
                notifier.printer_added.connect ((text, printer_uri, name, state, state_reasons, is_accepting_jobs) => {
                    unowned CUPS.Destination[] destinations = CUPS.get_destinations ();
                    foreach (unowned CUPS.Destination dest in destinations) {
                        if (dest.name == name) {
                            var printer = new Printer (dest);
                            list.add_printer (printer);
                        }
                    }
                });

                notifier.printer_deleted.connect ((text, printer_uri, name, state, state_reasons, is_accepting_jobs) => {
                   list.remove_printer (name);
                });

                new_subscription.begin ();
                Timeout.add_seconds (RENEW_INTERVAL, () => {
                    new_subscription.begin ();
                    return GLib.Source.CONTINUE;
                });

                if (default_printer != null) {
                    //Show printer page!
                }

                main_paned.show_all ();
            }

            return main_paned;
        }

        public override void shown () {
            
        }

        public override void hidden () {
            
        }

        public override void search_callback (string location) {
            
        }

        // 'search' returns results like ("Keyboard → Behavior → Duration", "keyboard<sep>behavior")
        public override async Gee.TreeMap<string, string> search (string search) {
            return new Gee.TreeMap<string, string> (null, null);
        }

        private string[] subscription_events = {
            "printer-added",
            "printer-deleted",
            "printer-stopped",
            "printer-state-changed",
            "job-created",
            "job-completed",
            null
        };

        private async void new_subscription () {
            if (subscription_id <= 0) {
                var request = new CUPS.IPP.IPP.request (CUPS.IPP.Operation.CREATE_PRINTER_SUBSCRIPTION);
                request.add_string (CUPS.IPP.Tag.OPERATION, CUPS.IPP.Tag.URI, "printer-uri", null, "/");
                request.add_string (CUPS.IPP.Tag.OPERATION, CUPS.IPP.Tag.NAME, "requesting-user-name", null, CUPS.get_user ());
                request.add_strings (CUPS.IPP.Tag.SUBSCRIPTION, CUPS.IPP.Tag.KEYWORD, "notify-events", null, subscription_events);
                request.add_string (CUPS.IPP.Tag.SUBSCRIPTION, CUPS.IPP.Tag.KEYWORD, "notify-pull-method", null, "ippget");
                request.add_string (CUPS.IPP.Tag.SUBSCRIPTION, CUPS.IPP.Tag.URI, "notify-recipient-uri", null, "dbus://");
                request.add_integer (CUPS.IPP.Tag.SUBSCRIPTION, CUPS.IPP.Tag.INTEGER, "notify-lease-duration", SUBSCRIPTION_DURATION);
                request.do_request (CUPS.HTTP.DEFAULT);
                if (request != null && request.get_status_code () <= CUPS.IPP.Status.OK_CONFLICT) {
                    unowned CUPS.IPP.Attribute attr = request.find_attribute ("notify-subscription-id", CUPS.IPP.Tag.INTEGER);
                    if (attr != null) {
                        subscription_id = attr.get_integer ();
                    } else {
                        critical ("No notify-subscription-id in response!");
                    }
                }
            } else {
                var request = new CUPS.IPP.IPP.request (CUPS.IPP.Operation.RENEW_SUBSCRIPTION);
                request.add_string (CUPS.IPP.Tag.OPERATION, CUPS.IPP.Tag.URI, "printer-uri", null, "/");
                request.add_string (CUPS.IPP.Tag.OPERATION, CUPS.IPP.Tag.NAME, "requesting-user-name", null, CUPS.get_user ());
                request.add_integer (CUPS.IPP.Tag.OPERATION, CUPS.IPP.Tag.INTEGER, "notify-subscription-id", subscription_id);
                request.add_integer (CUPS.IPP.Tag.SUBSCRIPTION, CUPS.IPP.Tag.INTEGER, "notify-lease-duration", SUBSCRIPTION_DURATION);
                request.do_request (CUPS.HTTP.DEFAULT);
                if (request != null && request.get_status_code () <= CUPS.IPP.Status.OK_CONFLICT) {
                    unowned CUPS.IPP.Attribute attr = request.find_attribute ("notify-subscription-id", CUPS.IPP.Tag.INTEGER);
                    if (attr != null) {
                        subscription_id = attr.get_integer ();
                    } else {
                        critical ("No notify-subscription-id in response!");
                    }
                }
            }
        }
    }
}

public Switchboard.Plug get_plug (Module module) {
    debug ("Activating Printers plug");
    var plug = new Printers.Plug ();
    return plug;
}
