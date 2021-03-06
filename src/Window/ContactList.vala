/*
* Copyright (c) {{yearrange}} Alex ()
*
* This program is free software; you can redistribute it and/or
* modify it under the terms of the GNU General Public
* License as published by the Free Software Foundation; either
* version 2 of the License, or (at your option) any later version.
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
* General Public License for more details.
*
* You should have received a copy of the GNU General Public
* License along with this program; if not, write to the
* Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
* Boston, MA 02110-1301 USA
*
* Authored by: Alex Angelou <>
*/

using Granite;
using Granite.Widgets;
using Gtk;

namespace Contacts {
    public class ContactList : Gtk.Paned {

        private Gtk.Stack contact_stack = new Gtk.Stack ();
        private Sidebar sidebar;

        construct {
            contact_stack.set_transition_type (Gtk.StackTransitionType.SLIDE_UP_DOWN);

            sidebar = new Sidebar (contact_stack);

            add (sidebar);
            add (contact_stack);
        }

        public void parse_local_vcard_threaded () {
            ThreadFunc<bool> append_local_contacts = () => {
                var ok = true;
                try {
                    initialize_list ();
                } catch (IOError e) {
                    stderr.printf (e.message + "\n");
                    ok = false;
                }
                return ok;
            };
            new Thread<bool> ("local_vcard", append_local_contacts);
        }

        private void initialize_list (Cancellable? cancellable = null) throws IOError {
            var home = Environment.get_home_dir ();
            File file = File.new_for_path (@"$home/.local/share/contacts/");
            FileEnumerator enumerator = file.enumerate_children (
                "standard::*",
                FileQueryInfoFlags.NOFOLLOW_SYMLINKS, 
                cancellable);

            FileInfo info = null;
            while (cancellable.is_cancelled () == false && ((info = enumerator.next_file (cancellable)) != null)) {
                if (info.get_name ().has_suffix (".vcf")) {
                    var list = parse_local_vcard (@"$home/.local/share/contacts/" + info.get_name ());
                    list.foreach ((contact) =>
                        contact_stack.add_named (contact, contact.title));
                    contact_stack.show_all ();
                }
            }

        	if (cancellable.is_cancelled ()) {
        		throw new IOError.CANCELLED ("Operation was cancelled");
        	}
        }


        private void set_contact_info(string line, Contact contact){
            var home = Environment.get_home_dir();
            if (line.has_prefix ("FN")){

                var needle = parse_needle (line);
                assert (needle != null);

                contact.set_title (needle);
                return;
           }
           if (line.has_prefix ("EMAIL")) {

                var type = parse_type (line);
                var needle = parse_needle (line);

                contact.new_email (needle, type);
                return;

            }
            if (line.has_prefix ("TEL")) {

                var type = parse_type (line);
                var needle = parse_needle (line);

                contact.new_phone (needle, type);
                return;

            }
            if (line.has_prefix ("ADR")) {

                var type = parse_type (line);
                var starting_needle = parse_needle (line);

                string[] needle = starting_needle.split (";", 0);

                if (needle.length >= 8)
                    contact.new_address ({needle[3], needle[4], needle[5], needle[6], needle[7]}, type);

                return;
            }
            if (line.has_prefix ("NOTE")) {

                var needle = parse_needle (line);
                contact.new_note (needle);

                return;
            }
            if (line.has_prefix ("URL")) {

                var needle = parse_needle (line);
                contact.new_website (needle);

                return;

            }
            if (line.has_prefix ("NICKNAME")) {

                var needle = parse_needle (line);
                contact.new_nickname (needle);

                return;
            }
            if (line.has_prefix ("BDAY")) {

                var needle = parse_needle (line);
                var year = int.parse (needle.substring (0, 4));
                var month = int.parse (needle.substring (4, 2));
                var day = int.parse (needle.substring (6, 2));
                contact.new_birthday (day, month, year);

                return;
            }
            if (line.has_prefix ("PHOTO")) {

                var needle = parse_needle (line);
                File image_file = File.new_for_path (home + "/.local/share/contacts/image.png");
                var os = image_file.replace (null, false, FileCreateFlags.PRIVATE);
                os.write (Base64.decode (needle));

                contact.set_image (home + "/.local/share/contacts/image.png");

                return;
            }
        }

        private List<Contact>? parse_local_vcard (string path) throws Error {
            File init_file = File.new_for_path (path);
            File file = File.new_for_path (path + ".temp");
            init_file.copy (file, FileCopyFlags.OVERWRITE);
            var dis = new DataInputStream (file.read ());
            var list = new List<Contact> ();
            var line = dis.read_line_utf8 (null);
            while (line != null) {
                var next_line = dis.read_line_utf8 (null);
                if (line != "BEGIN:VCARD" || next_line != "VERSION:3.0"){
                    line = dis.read_line_utf8 ();
                    continue;
                }

                var contact = new Contact ("");
                contact.saving = false;

                while (!((line = dis.read_line_utf8(null)) == "END:VCARD")){
                    set_contact_info(line, contact);
                }

                contact.name_changed.connect (() => {
                    sidebar.on_sidebar_changed ();
                });

                contact.saving = true;
                list.append (contact);

            }

            file.move (init_file, FileCopyFlags.OVERWRITE);

            return list;
        }

        private string parse_type (string line) {
            var type_start = line.up ().index_of ("TYPE=");
            var type_needle = line.slice (type_start+5, type_start+9).compress ();
            string type = "";

            switch (type_needle) {
                case "HOME":
                    type = DataTypes.HOME;
                    break;
                case "WORK":
                    type = DataTypes.WORK;
                    break;
                default:
                    type = DataTypes.OTHER;
                    break;
            }

            return type;
        }

        private string parse_needle (string line) {
            int start = 0;
            do {
                start = line.last_index_of_char (':', start);
            } while (line[start-1] == '\\');
            string needle = line.slice (start+1, line.length).compress ();

            return needle;
        }

        public void add_contact (string name) {
            var contact = new Contact (name);
            contact.name_changed.connect (() => {
                sidebar.on_sidebar_changed ();
            });

            contact_stack.add_named (contact, name.replace(" ", "_") + "_contact");
            contact_stack.show_all ();
        }
    }
}
