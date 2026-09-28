namespace :rubellum do
  desc "Prepare the database and recover interrupted app installations"
  task prepare: ["db:prepare", :environment] do
    AppPackageImport.recover!
  end
end
