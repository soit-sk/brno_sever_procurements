#!/usr/bin/env perl
# Copyright 2014-2015 Michal Špaček <tupinek@gmail.com>

# Pragmas.
use strict;
use warnings;

# Modules.
use Database::DumpTruck;
use Encode qw(decode_utf8 encode_utf8);
use English;
use HTML::TreeBuilder;
use LWP::UserAgent;
use POSIX qw(strftime);
use URI;
use Time::Local;

# Version.
our $VERSION = 0.02;

# Don't buffer.
$OUTPUT_AUTOFLUSH = 1;

# Certificate.
$ENV{'PERL_LWP_SSL_VERIFY_HOSTNAME'} = 0;

# URI of service.
my $base_uri = URI->new('https://uverejnovani.cz/profiles/details/statutarni-mesto-brno-mestska-cast-brno-sever');

# Open a database handle.
my $dt = Database::DumpTruck->new({
	'dbname' => 'data.sqlite',
	'table' => 'data',
});

# Create a user agent object.
my $ua = LWP::UserAgent->new(
	'agent' => 'Mozilla/5.0',
);

# Get base root.
print 'Page: '.$base_uri->as_string."\n";
my $root = get_root($base_uri);

# Look for items.
my $table = $root->find_by_attribute('class', 'list pz_offers');
my @tr = $table->find_by_tag_name('tbody')->find_by_tag_name('tr');
foreach my $tr (@tr) {
	my ($id, $name, $type, $published) = map {
		$tr->find_by_attribute('class', $_)->as_text;
	} qw(id name type published);
	my $link = $base_uri->scheme.'://'.$base_uri->host.
		$tr->find_by_attribute('class', 'actions')
		->find_by_tag_name('a')->attr('href');
	$published = get_db_datetime($published);

	# Save.
	my $ret_ar = eval {
		$dt->execute('SELECT COUNT(*) FROM data WHERE ID = ?',
			$id);
	};
	if ($EVAL_ERROR || ! @{$ret_ar} || ! exists $ret_ar->[0]->{'count(*)'}
		|| ! defined $ret_ar->[0]->{'count(*)'}
		|| $ret_ar->[0]->{'count(*)'} == 0) {

		print encode_utf8("$id: $name\n");
		$dt->insert({
			'ID' => $id,
			'Name' => $name,
			'Type' => $type,
			'Published' => $published,
			'Link' => $link,
		});
	}
}

# Get DB date from web datetime.
sub get_db_datetime {
	my $datetime = shift;
	my ($day, $mon, $year, $hour, $min) = $datetime
		=~ m/^\s*(\d+)\.(\d+)\.(\d+)\s+(\d+):(\d+)\s*$/ms;
	my $time = timelocal(0, $min, $hour, $day, $mon - 1, $year - 1900);
	return strftime('%Y-%m-%d', localtime($time));
}

# Get root of HTML::TreeBuilder object.
sub get_root {
	my $uri = shift;
	my $get = $ua->get($uri->as_string);
	my $data;
	if ($get->is_success) {
		$data = $get->content;
	} else {
		die "Cannot GET '".$uri->as_string." page.";
	}
	my $tree = HTML::TreeBuilder->new;
	$tree->parse(decode_utf8($data));
	return $tree->elementify;
}
