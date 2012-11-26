// with JQuery

jQuery(document).ready(function($){
  $('#user_and_today').click(function(){
    window.location.href = $(this).attr('link')
  })

});

function unifySummary() {
  jQuery('.entry_summary').hide()
  jQuery('#deal_summary_frame').show()
  jQuery('#deal_summary_mode').val('unified')
}

function splitSummary() {
  jQuery('#deal_summary_frame').hide()
  jQuery('.entry_summary').show()
  jQuery('#deal_summary_mode').val('split')
}