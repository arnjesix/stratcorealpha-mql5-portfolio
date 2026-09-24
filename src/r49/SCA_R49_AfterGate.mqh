bool AcceptBar(const datetime current_bar, datetime &last_bar)
{
   if(current_bar <= 0 || current_bar == last_bar)
      return false;
   last_bar = current_bar;
   return true;
}
