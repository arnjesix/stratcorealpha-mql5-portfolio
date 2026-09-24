bool AcceptBar(const datetime current_bar, datetime &last_bar)
{
   if(current_bar <= 0)
      return false;
   last_bar = current_bar;
   return true; // Defect: a second tick on the same bar is accepted.
}
