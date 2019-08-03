package SQLExpire;

use strict;
use warnings;
use Time::ParseDate;
use DBI;
use POSIX;

sub new {
    print "   SQLExpire::new called\n";
    my $type = shift;
    my $self = {'sql_connector' => shift};
    return bless $self, $type;
}

sub expire_check {
    # RETURN a hash of Check Attributes
    my ($self,$username,$check_hash,$reply_hash) = @_;

    if(!defined $username ){
        print "Empty value for username... return\n";
        return;
    }else{
        my $return_hash;

        if(exists $check_hash->{'GRASE-ExpireAfter'}){
            my $sql_query = 'SELECT AcctStartTime FROM radacct WHERE UserName = \'%{%k}\' AND AcctSessionTime >= 1 ORDER BY AcctStartTime LIMIT 1';

            #Filter out the ='%{%k}' to add our own user eg username='%{%k}'
            $sql_query      =~ s/%{%k}/$username/g;

            my $return_data = $self->{'sql_connector'}->query($sql_query);

            my $first_login = 0;
            my $now = time();
            if(defined($return_data->[0][0])){
                # We have a firstlogin date from the DB
                $first_login = parsedate($return_data->[0][0]);
            }else{
                # This is the users first login
                $first_login = $now;
            }

            ## Parse ExpireAfter with parsedate and NOW being first_login
            my $expiretime = parsedate($check_hash->{'GRASE-ExpireAfter'}, NOW => $first_login);

            if ($expiretime < $now) {
                # We have already passed our expiry time, just send a reject
                $return_hash->{'Reply-Message'} = "Your account has expired";
            }else{
                # We haven't yet passed our expiry time, adjust max session if
                # required
                my $expiretime_left = $expiretime - $now;
                if(exists $reply_hash->{'Session-Timeout'}){
                    my $current_val = $reply_hash->{'Session-Timeout'};
                    if ($expiretime_left < $current_val){
                        $return_hash->{'Session-Timeout'} = $expiretime_left;
                    }
                }else{
                        $return_hash->{'Session-Timeout'} = $expiretime_left;
                }
            }
        }
        return $return_hash;
    }
}

1;
