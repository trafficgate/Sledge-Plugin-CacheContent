package Sledge::Plugin::CacheContent;

use strict;
use vars qw($VERSION);
$VERSION = 0.03;

use Apache::File;
use Apache::Constants;
use Digest::MD5 qw(md5_hex);
use File::Spec;
use File::Path;

use vars qw($Debug);
$Debug = 0 unless defined $Debug;

sub import {
    my $class = shift;
    my $pkg   = caller;
    if ($pkg->isa('Sledge::Pages::Base')) {
	$pkg->register_hook(
	    AFTER_INIT => sub {
		my $self = shift;
		unless ($self->is_post_request) {
		    $self->add_filter(\&capture_output);
		}
	    },
	);
    }
}

sub capture_output {
    my($self, $content) = @_;
    my($dir, $file) = _map_filepath($self->r);
    warn "dir is $dir, file is $file" if $Debug;
    mkpath $dir, 0, 0777 unless -e $dir;

    my $fh = Apache::File->new("> $dir/$file") or die "$dir/$file: $!";
    print $fh $content;
    close $fh;

    my $ct = $self->r->content_type;
    warn "ct is $ct" if $Debug;
    my $out = Apache::File->new("> $dir/$file.ct") or die "$dir/$file.ct: $!";
    print $out $ct;
    close $out;

    return $content;
}

sub _map_filepath {
    my $r = shift;
    my $url = _build_url($r);
    my $key = $r->dir_config('SledgeCacheByUserAgent')
	? join("\t", $url, agent_name($r)) : $url;
    my $digest = md5_hex($key);
    my $base_dir = $r->dir_config('SledgeCacheDir') || '/tmp/Sledge-Plugin-Cache';

    my $dir = File::Spec->catfile($base_dir, substr($digest, 0, 1), substr($digest, 1, 1));
    return $dir, $digest;
}

sub agent_name {
    my $r = shift;
    require HTTP::MobileAgent;
    return HTTP::MobileAgent->new($r)->name;
}

sub _build_url {
    # same with Sledge::Pages::Base::current_url()
    my $r = shift;
    my $scheme = $ENV{HTTPS} ? 'https' : 'http';
    my $url = sprintf '%s://%s%s', $scheme, $r->header_in('Host'), $r->uri;
    $url .= '?' . $r->args if $r->args;
    return $url;
}

sub handler {
    my $r = shift;
    return DECLINED if ($r->main || $r->request_method eq 'POST');
    my($dir, $digest) = _map_filepath($r);

    my $file = "$dir/$digest";
    my $timeout = $r->dir_config('SledgeCacheTTL') || 60;
    if (-f $file && -M _ < ($timeout / (24 * 60))) {
	# leave it to Apache default handler
	warn "using cache file $file" if $Debug;

	my $in = Apache::File->new("$dir/$digest.ct");
	# don't care even if it doesn't exist
	if ($in) {
	    my $ct = <$in>;
	    close $in;
	    warn "restored ct is $ct" if $Debug;
	    $r->content_type($ct);
	}

	$r->filename($file);
	$r->handler('default-handler');
	return OK;
    }

    # don't use cache this time
    warn "don't use cache this time" if $Debug;
    return DECLINED;
}


1;
__END__

=head1 NAME

Sledge::Plugin::CacheContent - Generate and serve cached content

=head1 SYNOPSIS

  PerlTransHandler Sledge::Plugin::CacheContent
  <Files ~ \.cgi$>
  SetHandler perl-script
  PerlHandler Apache::Registry
  PerlSetVar SledgeCacheDir /home/sledge/cache
  PerlSetVar SledgeCacheTTL 120
  PerlSetVar SledgeCacheByUserAgent 1
  </Files>

  # in your Pages class
  use Sledge::Plugin::CacheContent;

=head1 DESCRIPTION

Sledge::Plugin::CacheContent はSledgeにより作成されるコンテンツを静的
にディスク出力し、TTLの範囲内で静的にサーブするmod_perl ハンドラです。

ユーザごとに変化しないコンテンツなどを出力する際にパフォーマンスの大き
な向上がのぞめます。mod_perl を EVERYTHING=1 でコンパイルしている必要
があります。

キャッシュの単位はURL(QUERY_STRING ふくむ)をベースとしていますので、

  /news/article.cgi?id=1
  /news/article.cgi?id=2

などは別のものとしてキャッシュされます。

=head1 OPTIONS

以下のオプション項目をPerlSetVarを利用して設定できます。

=over 4

=item SledgeCacheDir

キャッシュファイルが出力されるディレクトリ。デフォルトは /tmp/Sledge-Plugin-CacheContent

=item SledgeCacheTTL

キャッシュの生存期間(単位:分)。デフォルトは60

=item SledgeCacheByUserAgent

UserAgentごとにキャッシュを生成するオプション。携帯端末向けなど、フィルタリング
している場合に便利です。(フィルタリングが完了した後にキャッシュするよ
うに、このモジュールの use はフィルタ系プラグインの最後にしておく必要があります)
HTTP::MobileAgent モジュールが別途インストールされている必要があります。

=back

=head1 NOTE

初回アクセス時にキャッシュファイルを出力し、2度目以降はTTLをチェック後、
そのファイルをApacheのデフォルトハンドラにて出力するしくみになっていま
す。TTLチェックが失敗(TTLをオーバーしている)場合には、再度動的生成を行
いキャッシュファイルを更新します。

実際に Hello World! によるベンチマークをとってみると、(ab -n100 -c5でベンチ)

CacheContent使用

  Requests per second:    134.95 [#/sec] (mean)
  Time per request:       37.05 [ms] (mean)

CacheContent使用せず

  Requests per second:    27.26 [#/sec] (mean)
  Time per request:       183.40 [ms] (mean)

のように劇的にパフォーマンスが向上しています。

=head1 AUTHOR

Tatsuhiko Miyagawa E<lt>miyagawa@edge.jpE<gt>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

L<Apache::CacheContent>

=cut
