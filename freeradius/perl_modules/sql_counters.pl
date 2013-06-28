#!/usr/bin/perl

# Snippits taken from example.pl that comes with rlm_perl

use strict;
use warnings;

use lib "/etc/freeradius/perl_modules";
#use DatabaseConnection;
use SQLConnector;
use SQLCounter;
use Attributes;
use Data::Dumper;





#print Dumper $db->{'radius_db'}->selectall_hashref('SELECT * from radcheck', 'id');

# Bring the global hashes into the package scope
our (%RAD_REQUEST, %RAD_REPLY, %RAD_CHECK);

our $db;
our $sql_counter;
sub CLONE {

        $db = new SQLConnector();
        $db->prepare_statements();
        #$db = new DatabaseConnection();
    #Create a $sql_counter object which will read the counters defined once (its good to avoid unnecesary file reads)
    $sql_counter    = SQLCounter->new($db);
    $sql_counter->create_sql_counter_hash();
} 


# This the remapping of return values
#
use constant {
RLM_MODULE_REJECT => 0, # immediately reject the request
RLM_MODULE_OK	=> 2, # the module is OK, continue
RLM_MODULE_HANDLED	=> 3, # the module handled the request, so stop
RLM_MODULE_INVALID	=> 4, # the module considers the request invalid
RLM_MODULE_USERLOCK	=> 5, # reject the request (user is locked out)
RLM_MODULE_NOTFOUND	=> 6, # user not found
RLM_MODULE_NOOP	=> 7, # module succeeded without doing anything
RLM_MODULE_UPDATED	=> 8, # OK (pairs modified)
RLM_MODULE_NUMCODES	=> 9 # How many return codes there are
};

# Function to handle authorize
sub authorize {
        # For debugging purposes only
        # &log_request_attributes;

        # Here's where your authorization code comes
        # You can call another function from here:
        #&test_call;
        
        my $user = $RAD_REQUEST{'User-Name'};
        
        my $attributes = Attributes->new($db);

        my $check_hash = $attributes->check_attributes($user);        

        foreach my $checkkey (keys %RAD_CHECK){
            $check_hash->{$checkkey} = $RAD_CHECK{$checkkey};
        }
        
        my $sql_counter_reply = $sql_counter->counter_check($user,$check_hash);

        #print "======SQL Counter Reply=======\n";
        #print Dumper($sql_counter_reply);
        #print "==============================\n";

        if(defined $sql_counter_reply){

                foreach my $key (keys %{$sql_counter_reply}){

                        $RAD_REPLY{$key} = $sql_counter_reply->{$key};
                        #If there was an error the 'Reply-Message' will have a value, if so return with a 0
                        if($key eq 'Reply-Message'){ 
                                return RLM_MODULE_REJECT;
                        }
                }
        }        
        
        
        # TODO Only send UPDATED if we have actually changed things
        return RLM_MODULE_UPDATED;
}

# Function to handle authenticate
sub authenticate {
        # For debugging purposes only
        # &log_request_attributes;

        #if ($RAD_REQUEST{'User-Name'} =~ /^baduser/i) {
        #        # Reject user and tell him why
        #        $RAD_REPLY{'Reply-Message'} = "Denied access by rlm_perl function";
        #        return RLM_MODULE_REJECT;
        #} else {
        #        # Accept user and set some attribute
        #        $RAD_REPLY{'h323-credit-amount'} = "100";
                return RLM_MODULE_OK;
        #}
}
