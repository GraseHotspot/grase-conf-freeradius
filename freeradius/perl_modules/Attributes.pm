=head1 NAME

Attributes - A Module which will get the check and reply attributes for a user in FreeRADIUS mysql database

It will first get the group attributes and then override them if there are specific personal attributes declared

Part of YFi Hotspot Manager's custom rlm_perl module

=head1 VERSION

This documentation refers to Attributes version 0.1

=head1 SYNOPSIS

    use Attributes;
    use Data::Dumper;

    print Dumper(reply_attributes('alee'));
    print Dumper(check_attributes('alee'));


=head1 DESCRIPTION

This hash of attribute / value pairs can be used in the response of a Auth request from FreeRADIUS


=head1 AUTHOR

    Dirk van der Walt (dirkvanderwalt at gmail dot com)

=head1 LICENCE_AND_COPYRIGHT

Copyright (c) 2006 Dirk van der Walt (dirkvanderwalt at gmail dot com). All rights reserved.

This module is free software; you can redistribute it and/or 
modify it under the same terms as Perl itself. See L<perlartistic>.

This program is distributed in the hope that it will be usefull,
but WITHOUT ANY WARRANTY; without even implied warranty of
MERCHANTABILITY of FITNESS FOR A PARTICULAR PURPOSE.

=cut

package Attributes;

use strict;
use warnings;
use Data::Dumper;


#Initialise this with a sql_connector object
sub new {

    print "   Attributes::new called\n";
    my $type = shift;                       # The package/type name
    my $self = {'sql_connector' => shift};  # Reference to empty hash
    return bless $self, $type;
}


sub check_attributes {
#------------------------------------------------------------
#----RETURN a Hash of Check attributes ----------------------
#------------------------------------------------------------
    my ($self,$username) = @_;

    if(!defined $username ){

        print "Empty value for username... return\n";
        return;
    }else{

        return $self->_get_check_attributes($username);
    }
}

sub reply_attributes {
#------------------------------------------------------------
#----RETURN a Hash of Reply attributes ----------------------
#------------------------------------------------------------
    my ($self,$username) = @_;

    if(!defined $username ){

        print "Empty value for username... return\n";
        return;
    }else{

        return $self->_get_reply_attributes($username);
    }
}

sub _get_check_attributes {

    #-----------------------------------------------
    #--- This sub will do the following:
    #--- + Find out if the user is defined (in radcheck table)
    #--- + Find out which group the user belongs to (in radusergroup)
    #--- + Find the check attributes for the group
    #--- + override these check attributes if there are defined for the user itself in the radcheck table
    #--- + return a hash containing this attributes. 
    my ($self,$user) = @_;
    my $return_hash;

    #--- + Find out if the user is defined (in radcheck table)
    my $return_data    = $self->{'sql_connector'}->one_statement_value('radcheck_username',$user);

    if(!exists $return_data->{'value'}){
        print "User does not exists\n";
        return $return_hash;
    }

    #--- + Find out which group(s) the user belongs to (in radusergroup)
    #--- + Find the check attributes for the group
    $return_data    = $self->{'sql_connector'}->many_statement_value('radusergroup_username',$user);

    foreach my $line(@{$return_data}){

        my $check_group_name    = $line->[1];
        my $check_hash          = $self->_attributes_for_group($check_group_name,'check');

        if(defined $check_hash){
            foreach my $key (keys %{$check_hash}){
                $return_hash->{$key} = $check_hash->{$key};
            }
        }
    }

    #--- + override these check attributes if there are defined for the the user itself in the radcheck table
    $return_data    = $self->{'sql_connector'}->many_statement_value('radcheck_username',$user);

    foreach my $line(@{$return_data}){
        my $attribute               = $line->[2];
        my $value                   = $line->[4];
        $return_hash->{$attribute}  = $value;
    }
    return $return_hash;
}


sub _get_reply_attributes {

    #-----------------------------------------------
    #--- This sub will do the following:
    #--- + Find out if the user is defined (in radcheck table)
    #--- + Find out which group the user belongs to (in radusergroup)
    #--- + Find the reply attributes for the group
    #--- + override these reply attributes if there are defined for the the user itself in the radreply table
    #--- + return a hash containing this attributes. 
    my ($self,$user) = @_;
    my $return_hash;

    #--- + Find out if the user is defined (in radcheck table)
    my $return_data    = $self->{'sql_connector'}->one_statement_value('radcheck_username',$user);

    if(!exists $return_data->{'value'}){
        print "User does not exists\n";
        return $return_hash;
    }
 
    #--- + Find out which group(s) the user belongs to (in radusergroup)
    #--- + Find the reply attributes for the group
    $return_data    = $self->{'sql_connector'}->many_statement_value('radusergroup_username',$user);

    foreach my $line(@{$return_data}){

        my $reply_group_name    = $line->[1];
        my $reply_hash          = $self->_attributes_for_group($reply_group_name,'reply');

        if(defined $reply_hash){

            foreach my $key (keys %{$reply_hash}){
                $return_hash->{$key} = $reply_hash->{$key};
            }

        }
    }

    #--- + override these reply attributes if there are defined for the the user itself in the radreply table
    $return_data    = $self->{'sql_connector'}->many_statement_value('radreply_username',$user);
    foreach my $line(@{$return_data}){

        my $attribute               = $line->[2];
        my $value                   = $line->[4];
        $return_hash->{$attribute}  = $value;
    }
    return $return_hash;
}

sub _attributes_for_group {

    my ($self,$groupname,$type) = @_;

    my $query_string;
    my $return_hash;
    my $return_data;

    if($type eq 'check'){
        $return_data    = $self->{'sql_connector'}->many_statement_value('radgroupcheck_groupname',$groupname);
    }

    if($type eq 'reply'){
        $return_data    = $self->{'sql_connector'}->many_statement_value('radgroupreply_groupname',$groupname);
    }

    foreach my $line(@{$return_data}){

        my $attribute   = $line->[2];
        my $value       = $line->[4];
        $return_hash->{$attribute} = $value;
    }
    return $return_hash;
}

1;
