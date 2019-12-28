=head1 NAME

SQLCounter - A Module which will is used as a drop in replacement for sqlcounter.

This module was created due to the limitations of the sqlcounter module's handling of big numbers

=head1 VERSION

This documentation refers to SQLCounter version 0.1

=head1 SYNOPSIS

    use SQLCounter;
    use Data::Dumper;

    my $sql_counter_reply = sqlcounter_check($username, $check_hash);
    if(defined $sql_counter_reply){

        foreach my $key (keys %{$sql_counter_reply}){

            $RAD_REPLY{$key} = $sql_counter_reply->{$key};
            #If there was an error the 'Reply-Message' will have a value, if so return with a 0
            if($key eq 'Reply-Message'){
                return 0;
            }
        }
    }


=head1 DESCRIPTION

You have to pass it the $check_hash so it can check if the counter is tied to the specific user.
This hash of attribute / value pairs are returned which should be used to $RAD_REPLY


=head1 AUTHOR

    Dirk van der Walt (dvdwalt at csir dot co dot za)

=head1 LICENCE_AND_COPYRIGHT

Copyright (c) 2006 Dirk van der Walt (dirkvanderwalt at gmail dot com). All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.

This program is distributed in the hope that it will be usefull,
but WITHOUT ANY WARRANTY; without even implied warranty of
MERCHANTABILITY of FITNESS FOR A PARTICULAR PURPOSE.

=cut

package SQLCounter;

use strict;
use warnings;
use XML::Simple;
use Data::Dumper;
use DBI;
use POSIX;

#===============================================================
#===== CONFIGURATION DATA ======================================
#===============================================================
my $config_file = '/etc/freeradius/3.0/perl_modules/conf/settings.conf';
#===============================================================
#===== END of Configuration Data ===============================
#===============================================================


#Initialise this with a sql_connector object
sub new {

    print "   SQLCounter::new called\n";
    my $type = shift;                       # The package/type name

    my $xml     = new XML::Simple;
    my $data    = $xml->XMLin($config_file);
    my $self = {'config_file' => $config_file, 'config_data' => $data, 'sql_connector' => shift };  # Reference to empty hash
    return bless $self, $type;
}


sub counter_check {
#------------------------------------------------------------
#----RETURN a Hash of Check attributes ----------------------
#------------------------------------------------------------
    my ($self,$username,$check_hash) = @_;

    if(!defined $username ){

        print "Empty value for username... return\n";
        return;
    }else{

        my $return_hash;
        #Get a hash of all the defined sqlcounters (active or not)
        my $counters_detail = $self->{'counter_hash'};
        #print(Dumper($counters_detail));

        #Loop through a list of defined counters
        foreach my $key(keys(%{$counters_detail})){

            #print Dumper($check_hash);
            #Check if the couter is active
            if($counters_detail->{$key}{'active'}){

                #Determine the check attribute
                my $check_name = $counters_detail->{$key}{'check-name'};
                my $reply_name = $counters_detail->{$key}{'reply-name'};

                # Our reject reply-message when the counter is finished
                my $reply_message = $counters_detail->{$key}{'reply-message'};

                my $giga_reply_name = $counters_detail->{$key}{'giga-reply-name'};
                if(!defined $giga_reply_name){ ($giga_reply_name = $reply_name) =~ s/Octets/Gigawords/;}

                #Have we got a key like this? (in the $check_hash for the user)
                if(exists $check_hash->{$check_name}){

                    my $reset       = $counters_detail->{$key}{'reset'};
                    my $timestamp   = $self->get_timestamp($reset); #When should the reset time be
                    my $sql_query   = $counters_detail->{$key}{'query'};

                    #Filter out the ='%{%k}' to add our own user eg username='%{%k}'
                    $sql_query      =~ s/%\{%k}/$username/g;
                    #Filter out the '%b' and replace it wit the correct unix timestamp
                    $sql_query      =~ s/%b/$timestamp/g;
                    $sql_query      =~ s/"//g;
                    #  print "HEADS UP $sql_query\n";
                    #--- NOTE: This may be a performance bottleneck! because the 'prepare' happens every time ---
                    #--- IF performance is a problem --- start here!---------------------------------------------
                    #--------------------------------------------------------------------------------------------
                    my $return_data = $self->{'sql_connector'}->query($sql_query);
                    #--------------------------------------------------------------------------------------------
                    my $big_val     = $check_hash->{$check_name};

                    my $current_val =0;
                    if(defined($return_data->[0][0])){
                        $current_val = $return_data->[0][0];
                    }
                    my $result      = $big_val - ($current_val);
                    #print "NEED TO SUBTRACT $current_val FROM $big_val RESULT $result\n";
                    if($result <= 0){
                        #Some attribute values we want to return as a negative value
                        #---------------------------------------------------------
                        #--- YFi FEATURE : IGNORE Yfi-Data & Yfi-Time Depletion---
                        #---------------------------------------------------------
                        if(($reply_name eq 'Yfi-Data')or($reply_name eq 'Yfi-Time')){
                            $return_hash->{$reply_name} = $result;
                        }else{
                            ## This is where the reject messages are if they have finished a counter
                            $return_hash->{'Reply-Message'} = defined($reply_message) ? $reply_message : "Depleted value for $reply_name";
                        }
                    }else{
                        # Easiest way to see if we need Gigawords splitting is if the reply-name has Octets in it
                        if($reply_name =~ /Octets/)
                        {
                            my $int_max = 4294967296;
                            my $octets = 0;
                            my $gigawords = 0;
                            if($result >= $int_max)
                            {

                                # Split it into gigawords and octets
                                $octets = $result % $int_max;
                                $gigawords = int($result / $int_max);
                            }else{
                                $octets = $result;
                                $gigawords = 0;
                            }

                            if(exists $return_hash->{$reply_name}) {
                                my $current_val = $return_hash->{$reply_name};
                                my $current_gigawords = $return_hash->{$giga_reply_name};

                                if($gigawords <= $current_gigawords and $octets < $current_val) {
                                    $return_hash->{$reply_name} = $octets;
                                    $return_hash->{$giga_reply_name} = $gigawords;
                                }
                            } else {
                                $return_hash->{$reply_name} = $octets;
                                $return_hash->{$giga_reply_name} = $gigawords;
                            }

                        }elsif($reply_name =~ /Session-Timeout/) {
                            if(exists $return_hash->{$reply_name}) {
                                if($result < $return_hash->{$reply_name}) {
                                    $return_hash->{$reply_name} = $result;
                                }
                            } else {
                               $return_hash->{$reply_name} = $result;
                            }

                        }else{
                            $return_hash->{$reply_name} = $result;
                        }
                    }
                }
            }
        }
        return $return_hash;
    }
}

sub get_usage_for_counter {

    #------------------------------------------------
    #--- Get the usage (NOT the amount LEFT) --------
    #------------------------------------------------

    my ($self,$username,$counter_name) = @_;

    my $current_val;
    #Get a hash of all the defined sqlcounters (active or not)
    my $counters_detail = $self->{'counter_hash'};
    #Loop through a list of defined counters
    foreach my $key(keys(%{$counters_detail})){

        #Check if the couter is active
        if($counters_detail->{$key}{'active'} eq '1'){

            #print Dumper($counters_detail->{$key});
            #Determine the check attribute
            my $check_name = $counters_detail->{$key}{'check-name'};
            my $reply_name = $counters_detail->{$key}{'reply-name'};

            #is this the one we want
            if($counter_name eq $counters_detail->{$key}{'counter-name'}){      #Is this the counter that we want??

                my $reset       = $counters_detail->{$key}{'reset'};
                my $timestamp   = $self->get_timestamp($reset); #When should the reset time be
                my $sql_query   = $counters_detail->{$key}{'query'};
                #Filter out the ='%{%k}' to add our own user eg username='%{%k}'
                $sql_query      =~ s/%\{%k}/$username/g;
                #Filter out the '%b' and replace it wit the correct unix timestamp
                $sql_query      =~ s/%b/$timestamp/g;
                $sql_query      =~ s/"//g;
                my $return_data = $self->{'sql_connector'}->query($sql_query);
                $current_val = $return_data->[0][0];
            }
        }
    }
    return $current_val;
}

#-----------------------------
#---Sub to build a hash of  --
#---each sqlcounter-----------
#-----------------------------
sub create_sql_counter_hash {

    my ($self) = @_;

    my $counter_record = 0;
    my $counter_name;
    my $sql_counter_hash;
    my $sql_counter_file = $self->{'config_data'}->{radius_conf}->{sql_counter_file};

    my @sql_counter_raw = `cat $sql_counter_file`;
    foreach my $line (@sql_counter_raw){
        chomp $line;

        #BEGIN THE RECORDING
        if($line =~ m/^\s*sqlcounter/){
            $counter_record = 1;
            $counter_name = $line;
            $counter_name =~ s/^\s*sqlcounter\s*//;
            $counter_name =~ s/\s+{//;
            #print "COUNTER FOUND $counter_name\n";
            $sql_counter_hash->{$counter_name}{'active'} = $self->find_if_sqlcounter_is_active($counter_name);
        }

        if(($counter_record)&&($line =~ m/\s*counter-name/)){
            $sql_counter_hash->{$counter_name}{'counter-name'} = $self->get_sql_counter_atom($line);
        }

        if(($counter_record)&&($line =~ m/\s*check-name/)){
            $sql_counter_hash->{$counter_name}{'check-name'} = $self->get_sql_counter_atom($line);
        }

        if(($counter_record)&&($line =~ m/\s*reply-name/)){
            $sql_counter_hash->{$counter_name}{'reply-name'} = $self->get_sql_counter_atom($line);
        }

        if(($counter_record)&&($line =~ m/\s*reply-message/)){
            $line =~ s/\s*reply-message\s*=\s*//;
            $line =~ s/^"//;
            $line =~ s/"$//;
            $sql_counter_hash->{$counter_name}{'reply-message'} = $line;
        }

        if(($counter_record)&&($line =~ m/\s*gigareplyname/)){
            $sql_counter_hash->{$counter_name}{'giga-reply-name'} = $self->get_sql_counter_atom($line);
        }

        if(($counter_record)&&($line =~ m/\s*sqlmod-inst/)){
            $sql_counter_hash->{$counter_name}{'sqlmod-inst'} = $self->get_sql_counter_atom($line);
        }

        if(($counter_record)&&($line =~ m/\s*key/)){
            $sql_counter_hash->{$counter_name}{'key'} = $self->get_sql_counter_atom($line);
        }

        if(($counter_record)&&($line =~ m/\s*reset/)){
            $sql_counter_hash->{$counter_name}{'reset'} = $self->get_sql_counter_atom($line);
        }

        if(($counter_record)&&($line =~ m/\s*query/)){
            $line =~ s/\s*query\s*=\s*//;
            $sql_counter_hash->{$counter_name}{'query'} = $line;
        }

        #END THE RECORDING
        if($line =~ m/^\s*}/){
            $counter_record = 0;
           # print "COUNTER END $counter_name\n";
        }
    }

    $self->{'counter_hash'} = $sql_counter_hash;
}

sub get_sql_counter_atom {
    my ($self,$line) = @_;

    $line =~ s/.+\s*=\s*//;
    return $line;
}


sub find_if_sqlcounter_is_active {

    my ($self,$sql_counter_name) = @_;
    my @auth_section_ent    = $self->get_active_counters_from_settings();

    foreach my $entry (@auth_section_ent){

        if($entry eq $sql_counter_name){
            return 1;
        }
    }
    return 0;
}


sub get_active_counters_from_settings {

    my ($self) = @_;
    my @active_counters;
    foreach my $counter(@{$self->{'config_data'}->{sql_counters}{'counter'}}){
        push(@active_counters,$counter);
    }
    return @active_counters;
}


sub get_timestamp {

    my($self,$reset) = @_;

    if($reset eq "monthly"){
        return $self->start_of_month();
    }

    if($reset eq "weekly"){
        return start_of_week();
    }

     if($reset eq "daily"){
        return start_of_day();
    }

     if($reset eq "hourly"){
        return start_of_hour();
    }
    return mktime (0, 0, 0, 1, 1, (2004 - 1900), 0, 0);
}



sub start_of_month {

    my($self) = @_;

    #Get the current timestamp;
    #-------------------------------------------------------
    #--- If we need to reset the user's account on the 25---
    #-------------------------------------------------------
    my $reset_on = $self->{'config_data'}->{sql_counters}{start_of_month};    #New Feature which lets you decide when the monthly CAP will reset
    my $unixtime;

    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
    if($mday < $reset_on ){
        $unixtime = mktime (0, 0, 0, $reset_on, $mon-1, $year, 0, 0);   #We use the previous month
    }else{
        $unixtime = mktime (0, 0, 0, $reset_on, $mon, $year, 0, 0);     #We use this month
    }
    #printf "%4d-%02d-%02d %02d:%02d:%02d\n",$year+1900,$mon+1,$mday,$hour,$min,$sec;
    #create a new timestamp:
    return $unixtime;
}

sub start_of_week {

    #Get the current timestamp;
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
    #create a new timestamp:
    my $unixtime = mktime (0, 0, 0, $mday-$wday, $mon, $year, 0, 0);
    return $unixtime;

    #Debug info
    #($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime($unixtime);
    #printf "%4d-%02d-%02d %02d:%02d:%02d\n",
    #$year+1900,$mon+1,$mday,$hour,$min,$sec;
}

sub start_of_day {

    #Get the current timestamp;
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
    #create a new timestamp:
    my $unixtime = mktime (0, 0, 0, $mday, $mon, $year, 0, 0);
    return $unixtime;

    #Debug info
    #($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime($unixtime);
    #printf "%4d-%02d-%02d %02d:%02d:%02d\n",
    #$year+1900,$mon+1,$mday,$hour,$min,$sec;
}

sub start_of_hour {

    #Get the current timestamp;
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
    #create a new timestamp:
    my $unixtime = mktime (0, 0, $hour, $mday, $mon, $year, 0, 0);
    return $unixtime;

    #Debug info
    #($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime($unixtime);
    #printf "%4d-%02d-%02d %02d:%02d:%02d\n",
    #$year+1900,$mon+1,$mday,$hour,$min,$sec;
}

1;
