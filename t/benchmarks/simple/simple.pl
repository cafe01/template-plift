#!/usr/bin/env perl
use strict;
use 5.010;
use Benchmark ':all';
use FindBin;
use lib "$FindBin::Bin/../../../lib";
use Plift;
use Template::Pure;
use Path::Tiny;
use Template;
use HTML::Template;
use XML::LibXML::jQuery;


my $plift = Plift->new( path => ["$FindBin::Bin/plift"] );
my $tt = Template->new( INCLUDE_PATH => ["$FindBin::Bin/tt"] );



# print "Plift:\n".plift().plift(); exit;
# print "Pure:\n".pure();
# print "TT:\n".tt(); exit;
# print "HTML::Template:\n".html_template(); exit;

my @jquery_cache = map {$_->document->clone } jquery_parse_files();
# say "@jquery_cache";

cmpthese(shift || 5000, {
    Plift => \&plift,
    'HTML::Template'  => \&html_template,
    # 'Template::Pure'  => \&pure,
    # 'Template::Toolkit'  => \&tt,
    # read_files => \&read_files,
    # jquery_parse_files => \&jquery_parse_files,
    # jquery_clone_nodes => \&jquery_clone_nodes,
});



sub plift {
    my $output = $plift->process("index")->as_html;
}

sub html_template {

    my $html_template = HTML::Template->new( path => ["$FindBin::Bin/html_template"], filename => 'layout.html' );
    my $output = $html_template->output;
}


sub pure {

    my $footer = Template::Pure->new(
        template => path("$FindBin::Bin/pure/footer.html")->slurp_utf8,
        directives => []);

    my $header = Template::Pure->new(
        template => path("$FindBin::Bin/pure/header.html")->slurp_utf8,
        directives => []);

    my $layout = Template::Pure->new(
        template   => path("$FindBin::Bin/pure/layout.html")->slurp_utf8,
        directives => [ '#content+' => 'content' ]
    );

    my $index = Template::Pure->new(
        template => path("$FindBin::Bin/pure/index.html")->slurp_utf8,
        directives => []);

    my $output = $index->render({
        layout => $layout,
        header => $header,
        footer => $footer,
    });
}

sub tt {

    my $output = '';

    $tt->process('index.html', {}, \$output)
        || die $tt->error();

    $output;
}

sub read_files {

    my $file = path("$FindBin::Bin/pure/footer.html")->slurp_utf8;
    $file = path("$FindBin::Bin/pure/header.html")->slurp_utf8;
    $file = path("$FindBin::Bin/pure/layout.html")->slurp_utf8;
    $file = path("$FindBin::Bin/pure/index.html")->slurp_utf8;
}


sub jquery_parse_files {

    my @parsed = (
        j(path("$FindBin::Bin/pure/footer.html")->slurp_utf8),
        j(path("$FindBin::Bin/pure/header.html")->slurp_utf8),
        j(path("$FindBin::Bin/pure/layout.html")->slurp_utf8),
        j(path("$FindBin::Bin/pure/index.html")->slurp_utf8),
    );
}



sub jquery_clone_nodes {
    my @clones = map {
        my $dom = $_->clone->contents;
        $dom->append_to($dom->document);
        $dom;

    } @jquery_cache;


}
