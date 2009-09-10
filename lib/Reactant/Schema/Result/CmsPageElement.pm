package Reactant::Schema::Result::CmsPageElement;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("InflateColumn::DateTime", "TimeStamp", "EncodedColumn", "Core");
__PACKAGE__->table("cms_page_element");
__PACKAGE__->add_columns(
  "id",
  { data_type => "INT", default_value => undef, is_nullable => 0, size => 11 },
  "page",
  { data_type => "INT", default_value => undef, is_nullable => 0, size => 11 },
  "name",
  {
    data_type => "VARCHAR",
    default_value => undef,
    is_nullable => 0,
    size => 50,
  },
  "content",
  {
    data_type => "TEXT",
    default_value => undef,
    is_nullable => 1,
    size => 65535,
  },
);
__PACKAGE__->set_primary_key("id");
__PACKAGE__->belongs_to("page", "Reactant::Schema::Result::CmsPage", { id => "page" });


# Created by DBIx::Class::Schema::Loader v0.04006 @ 2009-09-08 14:28:52
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:ynV+43BqU9WgX9veAWhmiQ


# You can replace this text with custom content, and it will be preserved on regeneration
1;
