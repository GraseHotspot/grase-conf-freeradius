package SQLConnector;

use strict;
use Data::Dumper;
use DBI;
#use XML::Simple;
use Config::Simple;


sub new {

    print "   SQLConnector::new called\n";
    my $type = shift;            # The package/type name
    #my $self = {'config_file' => '/etc/grase/radius.conf'};               # Reference to empty hash
   
    my $self = {};
    my $self->{'radiusconfig'} = {};
    Config::Simple->import_from('/etc/grase/radius.conf', $self->{'radiusconfig'}) || die "Couldn't read our config file for database details in SQLConnector" . Config::Simple->error(); 
    
    print Dumper $self;  
    
    my $db_server               = $self->{'radiusconfig'}->{'sql_server'};
    my $db_name                 = $self->{'radiusconfig'}->{'sql_database'};
    my $db_user                 = $self->{'radiusconfig'}->{'sql_username'};
    my $db_password             = $self->{'radiusconfig'}->{'sql_password'};

    $self->{'db_handle'}             =   DBI->connect("DBI:mysql:database=$db_name;host=$db_server",
                                     "$db_user", 
                                     "$db_password",
                                     { RaiseError => 1,
                                       AutoCommit => 1,
                                       FetchHashKeyName => "NAME_lc" }) || die "Unable to connect to $db_server because $DBI::errstr";
    $self->{'db_handle'}->{'mysql_auto_reconnect'} = 1;
    return bless $self, $type;
}


sub DESTROY
{
   print "   SQLConnector::DESTROY called\n";
}


sub query {
    my($self,$q)        = @_;
    my $StatementHandle = $self->{'db_handle'}->prepare("$q");
    $StatementHandle->execute();
    return $StatementHandle->fetchall_arrayref();
}


sub prepare_statements {

    my($self,$q)        = @_;
    #____________ Description ____________________________________________________
    #__ This file prepares the various SQL queries which will later be executed___
    #_____________________________________________________________________________

    #List the statements here so we can loop through them and 'finish' them
    $self->{'statements'}   =   [ 
                                    'na_nasname', 'na_id', 'device_name','device_update_id', 'user_id', 'user_username','radcheck_username',
                                    'realm_id', 'radacct_count_username', 'radacct_time_username', 'na_realm_na_id', 'radusergroup_username',
                                    'radgroupcheck_groupname', 'radgroupreply_groupname', 'radcheck_username', 'radreply_username'
                                ];

    #==================================================
    #=== Return only ONE line / Require One value =====
    #==================================================

    #____ NAS Related Queries _______
    $self->{'na_nasname'}       = $self->{'db_handle'}->prepare("SELECT * FROM nas WHERE nasname=?");
    $self->{'na_id'}            = $self->{'db_handle'}->prepare("SELECT * FROM nas WHERE id=?");

    #____ Devices Related Queries _______
    $self->{'device_name'}      = $self->{'db_handle'}->prepare("SELECT * FROM devices WHERE name=?");
    $self->{'device_update_id'} = $self->{'db_handle'}->prepare("UPDATE devices SET modified=now() WHERE id=?");

    #____ Users Related Queries ________
    $self->{'user_id'}          = $self->{'db_handle'}->prepare("SELECT * FROM users WHERE id=?");
    $self->{'user_username'}    = $self->{'db_handle'}->prepare("SELECT * FROM users WHERE username=?");

     #____ Radcheck Queries _______
    $self->{'radcheck_username'}  = $self->{'db_handle'}->prepare("SELECT value FROM radcheck WHERE username=? and attribute='Cleartext-Password'");

    #_____ Realm Related Queries _____
    $self->{'realm_id'}           = $self->{'db_handle'}->prepare("SELECT * FROM realms WHERE id=?");

    #_____ Radacct Queries ______
    $self->{'radacct_count_username'} = $self->{'db_handle'}->prepare("SELECT COUNT(*) as count FROM radacct WHERE username=? AND acctstoptime is NULL");
    $self->{'radacct_time_username'}  = $self->{'db_handle'}->prepare("SELECT UNIX_TIMESTAMP(acctstarttime) as acctstarttime FROM radacct WHERE username=? ORDER BY acctstarttime ASC LIMIT 1");
    $self->{'radacct_sum_username'}   = $self->{'db_handle'}->prepare("SELECT SUM(acctinputoctets) as input, SUM(acctoutputoctets) as output, SUM(acctsessiontime) as time FROM radacct where username=?");
    $self->{'credit_sum_used_by_id'}  = $self->{'db_handle'}->prepare("SELECT SUM(data) as data, SUM(time) as time FROM credits where used_by_id=?");

    #_____ Prime / Normal differentiation _____
    $self->{'times_last_entry'}     = $self->{'db_handle'}->prepare("SELECT * from times where acctsessionid=? ORDER BY id DESC LIMIT 1");
   


    #==================================================
    #=== Return only ONE line / Require Three values=====
    #==================================================
    #____ Extra CAPS ______
    $self->{'extra_sum'}            = $self->{'db_handle'}->prepare("SELECT SUM(value) as sum FROM extras WHERE user_id=? AND type=? AND UNIX_TIMESTAMP(created) > ?");
    #____ Prime Time / Normal Time ____
    $self->{'prime_totals'}         = $self->{'db_handle'}->prepare("SELECT SUM(data) as data, SUM(time) as time FROM times where UNIX_TIMESTAMP(created) >= ? AND UNIX_TIMESTAMP(created) <= ? AND username=? AND type='Prime'");
    $self->{'normal_totals_start'}  = $self->{'db_handle'}->prepare("SELECT SUM(data) as data, SUM(time) as time FROM times where UNIX_TIMESTAMP(created) >= ? AND UNIX_TIMESTAMP(created) <= ? AND username=? AND type='Normal'");
    $self->{'normal_totals_end'}    = $self->{'db_handle'}->prepare("SELECT SUM(data) as data, SUM(time) as time FROM times where UNIX_TIMESTAMP(created) >= ? AND username=? AND type='Normal' AND UNIX_TIMESTAMP(modified) <= ?");


    #==================================================
    #=== Return ziltzh / Require Two values============
    #==================================================

    $self->{'user_update_data'}     = $self->{'db_handle'}->prepare("UPDATE users SET data=? WHERE id=?");
    $self->{'user_update_time'}     = $self->{'db_handle'}->prepare("UPDATE users SET time=? WHERE id=?");


    #==================================================
    #=== Return many lines / Require One value ========
    #==================================================
    $self->{'na_realm_na_id'}           = $self->{'db_handle'}->prepare("SELECT * FROM na_realms WHERE na_id=?");
    $self->{'radusergroup_username'}    = $self->{'db_handle'}->prepare("SELECT * FROM radusergroup WHERE username=? ORDER BY priority");
    $self->{'radgroupcheck_groupname'}  = $self->{'db_handle'}->prepare("SELECT * FROM radgroupcheck WHERE groupname=?");
    $self->{'radgroupreply_groupname'}  = $self->{'db_handle'}->prepare("SELECT * FROM radgroupreply WHERE groupname=?");
    $self->{'radcheck_username'}        = $self->{'db_handle'}->prepare("SELECT * FROM radcheck WHERE username=?");
    $self->{'radreply_username'}        = $self->{'db_handle'}->prepare("SELECT * FROM radreply WHERE username=?");

    #====================================================
    #=== Return Zitzh / Require Five Values =============
    #====================================================
    $self->{'update_times_entry'}     = $self->{'db_handle'}->prepare("UPDATE times SET time= ?, data= ?, modified=now() where id = ?");

    #====================================================
    #=== Return Zitzh / Require Five Values =============
    #====================================================
    $self->{'add_times_entry'}     = $self->{'db_handle'}->prepare("INSERT INTO times(acctsessionid, username, time, data, type, created, modified) VALUES(?,?,?,?,?,now(),now())");


    #=======================================================
    #==== SQL Counter Quick ================================
    #=======================================================
    #$self->{'yfi_max_bytes_monthly'}    = $self->{'db_handle'}->prepare("SELECT SUM(acctinputoctets - GREATEST((? - UNIX_TIMESTAMP(acctstarttime)), 0))+ SUM(acctoutputoctets -GREATEST((? - UNIX_TIMESTAMP(acctstarttime)), 0)) FROM radacct WHERE username=? AND UNIX_TIMESTAMP(acctstarttime) + acctsessiontime > ?"


# 
#     $self->{'user_count'}         = $self->{'db_handle'}->prepare("SELECT COUNT(*) FROM users WHERE username=?");
# 
#     $self->{'user_detail_for_name'}  = $self->{'db_handle'}->prepare("SELECT id,cap,active FROM users WHERE username=?");
#     $self->{'user_username'}      = $self->{'db_handle'}->prepare("SELECT username FROM users WHERE id=?");
# 
#     $self->{'user_id'}            = $self->{'db_handle'}->prepare("SELECT SUM(value) FROM extras WHERE user_id=? AND type=? AND UNIX_TIMESTAMP(created) > ?");
# 
#     #For the Voucher Module:
#     $self->{'radacct_username'}   = $self->{'db_handle'}->prepare("SELECT DISTINCT username FROM radacct WHERE nasipaddress=?");
#     $self->{'radacct_start'}      = $self->{'db_handle'}->prepare("SELECT UNIX_TIMESTAMP(acctstarttime) FROM radacct WHERE username=? ORDER BY acctstarttime ASC LIMIT 1");

#     $self->{'radcheck_password'} = $self->{'db_handle'}->prepare("SELECT value FROM radcheck WHERE username=? and attribute='Cleartext-Password'");
}


#_____________________________________________________________
#______________ NAS Related Methods___________________________
#_____________________________________________________________

#Only return one line for the query of a nasname
sub one_statement_value {   #Select the statement handle name and supply the value

    my($self,$statement_name,$value)  = @_;

    $self->{"$statement_name"}->execute($value)
        or die "Couldn't execute statement: " .$self->{$statement_name}->errstr;

    my $hash_ref        = $self->{$statement_name}->fetchrow_hashref();
    return $hash_ref;   # Return a hash with ALL the fields in the NAS 
}

sub one_statement_no_return {
    my($self,$statement_name,$value)  = @_;

    my $fb = $self->{"$statement_name"}->execute($value)
        or die "Couldn't execute statement: " .$self->{$statement_name}->errstr;

    #Auto Commmit had to be turned on because of mysql_auto_reconnect
    #$self->{"db_handle"}->commit();

    return;
}


sub one_statement_no_return_value_value {
    my($self,$statement_name,$value1,$value2)  = @_;

    my $fb = $self->{"$statement_name"}->execute($value1,$value2)
        or die "Couldn't execute statement: " .$self->{$statement_name}->errstr;

    #Auto Commmit had to be turned on because of mysql_auto_reconnect
    #$self->{"db_handle"}->commit();
    return;
}

sub no_return_three_values {

    my($self,$statement_name,$value1,$value2,$value3) = @_;
    my $fb = $self->{"$statement_name"}->execute($value1,$value2,$value3)
        or die "Couldn't execute statement: " .$self->{$statement_name}->errstr;
    #Auto Commmit had to be turned on because of mysql_auto_reconnect
    #$self->{"db_handle"}->commit();
    return;
}

sub no_return_five_values {

    my($self,$statement_name,$value1,$value2,$value3,$value4,$value5) = @_;
    my $fb = $self->{"$statement_name"}->execute($value1,$value2,$value3,$value4,$value5)
        or die "Couldn't execute statement: " .$self->{$statement_name}->errstr;
    #Auto Commmit had to be turned on because of mysql_auto_reconnect
    #$self->{"db_handle"}->commit();
    return;
}


#Only return one line for the query 
sub one_statement_value_value_value {   #Select the statement handle name and supply the value

    my($self,$statement_name,$value1,$value2,$value3)  = @_;

    $self->{"$statement_name"}->execute($value1,$value2,$value3)
        or die "Couldn't execute statement: " .$self->{$statement_name}->errstr;

    my $hash_ref        = $self->{$statement_name}->fetchrow_hashref();
    return $hash_ref;   # Return a hash with ALL the fields in the NAS 
}


sub many_statement_value {

    my($self,$statement_name,$value)  = @_;

    $self->{"$statement_name"}->execute($value)
        or die "Couldn't execute statement: " .$self->{$statement_name}->errstr;

    my $array_ref        = $self->{$statement_name}->fetchall_arrayref();
    return $array_ref;   # Return a hash with ALL the fields in the NAS 
}



sub finish_statements {   #Select the statement handle name and supply the value

    my($self)  = @_;

    foreach my $item(@{$self->{statements}}){

       # print "Destroying statement handle: $item\n";
        $self->{$item}->finish();

    }
}



1;
