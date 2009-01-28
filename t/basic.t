use strict;
use warnings;
use lib './lib';
use Perlbal::Test;
use Perlbal::Test::WebServer;
use Perlbal::Test::WebClient;
use Test::Declare;
use Path::Class;

my %hosts = (
    'conf1.intra' => +{
        sv_name   => 'conf1',
        docroot   => tempdir(),
        conf_path => './t/conf/conf1.conf',
    },
    'conf2.intra' => +{
        sv_name   => 'conf2',
        docroot => tempdir(),
        conf_path => './t/conf/conf2.conf',
    },
);

plan tests => scalar(keys %hosts) * 2;

for my $host (keys %hosts) {
    my $fh = file($hosts{$host}->{conf_path})->openw;
    print $fh qq{
        CREATE SERVICE $hosts{$host}->{sv_name}
            SET role          = web_server
            SET docroot       = $hosts{$host}->{docroot}
            SET enable_put    = 1
            SET enable_delete = 1
        ENABLE $hosts{$host}->{sv_name}

        CREATE SERVICE http_server
            SET listen          = 127.0.0.1:1919
            SET role            = selector
            SET plugins         = VHOSTS
            VHOST $host = $hosts{$host}->{sv_name}
        ENABLE http_server
    }
}

my $conf = qq{
LOAD VHOSTS
LOAD ConfLoader
};

for my $host (keys %hosts) {
    $conf.= qq{
        LOAD_CONF = $hosts{$host}->{conf_path}
    };
}

# start perlbal
Perlbal::Test::start_server($conf) or die qq{can't start testing perlbal.\n};

# create perlbal test client
my $wc = Perlbal::Test::WebClient->new;
$wc->server('127.0.0.1:1919');
$wc->keepalive(1);
$wc->http_version('1.0');

# put host data
for my $host (keys %hosts) {
    $wc->request({
        method  => "PUT",
        content => 'I am '.$host,
        host    => $host,
    }, 'app');
}

# do test test test!
describe "Perlbal::Plugin::ConfLoader's test" => run {

    for my $host (keys %hosts) {
        test "$host" => run {
            my $res = $wc->request({ host => $host}, 'app');
            ok $res;
            is $res->content, 'I am '.$host;
        };
    }
};

cleanup {
    for my $host (keys %hosts) {
        unlink $hosts{$host}->{conf_path};
    }
};

